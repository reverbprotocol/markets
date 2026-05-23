// SPDX-License-Identifier: Apache-2.0
// Entry. Wires the panels together. No frameworks.

import { loadConfig, saveConfig } from "./config";
import type { ReverbConfig } from "./config";
import { buildChain, connectWallet, publicClientFor } from "./wallet";
import type { Address, PublicClient, WalletClient } from "viem";
import { aggregateFills, loadAllMarkets, loadMarket, matchOrders, redeem, STATE_NAMES } from "./operator";
import commitmentConfig from "./commitment.json";
import {
  parseSignedOrder,
  serializeSignedOrder,
  signOrder,
} from "./orders";

interface State {
  config: ReverbConfig | null;
  pub: PublicClient | null;
  walletClient: WalletClient | null;
  account: Address | null;
}

const state: State = {
  config: loadConfig(),
  pub: null,
  walletClient: null,
  account: null,
};

function $(id: string): HTMLElement {
  const el = document.getElementById(id);
  if (!el) throw new Error(`missing element #${id}`);
  return el;
}

function setStatus(id: string, text: string, kind: "ok" | "warn" | "err" = "ok"): void {
  const el = $(id);
  el.textContent = text;
  el.className = `status-${kind}`;
}

function renderConfigForm(): void {
  const form = $("config-form") as HTMLFormElement;
  if (state.config) {
    (form.elements.namedItem("chainId") as HTMLInputElement).value = String(state.config.chainId);
    (form.elements.namedItem("operator") as HTMLInputElement).value = state.config.operator;
    (form.elements.namedItem("escrow") as HTMLInputElement).value = state.config.escrow;
    (form.elements.namedItem("token") as HTMLInputElement).value = state.config.token;
  }
}

function renderWalletBar(): void {
  const bar = $("wallet-bar");
  if (state.account) {
    bar.innerHTML = `connected: <code>${state.account}</code>`;
  } else {
    bar.innerHTML = `<button id="connect-btn">connect wallet</button> <span class="status-warn">not connected</span>`;
    $("connect-btn").addEventListener("click", () => void onConnect());
  }
}

async function onConnect(): Promise<void> {
  if (!state.config) {
    setStatus("config-status", "save config first", "warn");
    return;
  }
  try {
    const cfg = buildChain(state.config.chainId);
    const { address, walletClient } = await connectWallet(cfg);
    state.account = address;
    state.walletClient = walletClient;
    state.pub = publicClientFor(cfg);
    renderWalletBar();
  } catch (e) {
    setStatus("config-status", `connect failed: ${(e as Error).message}`, "err");
  }
}

function bindConfigForm(): void {
  const form = $("config-form") as HTMLFormElement;
  form.addEventListener("submit", (ev) => {
    ev.preventDefault();
    const fd = new FormData(form);
    const cfg: ReverbConfig = {
      chainId: Number(fd.get("chainId")),
      operator: fd.get("operator") as Address,
      escrow: fd.get("escrow") as Address,
      token: fd.get("token") as Address,
    };
    saveConfig(cfg);
    state.config = cfg;
    state.pub = publicClientFor(buildChain(cfg.chainId));
    setStatus("config-status", "saved", "ok");
  });
}

function bindLoadMarketForm(): void {
  const form = $("load-market-form") as HTMLFormElement;
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const info = $("market-info");
    info.textContent = "loading...";
    if (!state.config || !state.pub) {
      info.textContent = "save config first";
      return;
    }
    const fd = new FormData(form);
    const id = BigInt(String(fd.get("marketId")));
    try {
      const m = await loadMarket(state.pub, state.config.operator, id);
      info.innerHTML = `
        <pre>marketId          : ${m.marketId}
questionHash      : ${m.questionHash}
settlementToken   : ${m.settlementToken}
resolver          : ${m.resolver}
resolutionDeadline: ${m.resolutionDeadline} (${new Date(Number(m.resolutionDeadline) * 1000).toISOString()})
challengeWindow   : ${m.challengeWindowSeconds}s
proposedAt        : ${m.proposedAt} ${m.proposedAt > 0n ? `(${new Date(Number(m.proposedAt) * 1000).toISOString()})` : ""}
state             : ${m.state} (${STATE_NAMES[m.state] ?? "?"})
winningOutcome    : ${m.winningOutcome}
totalCollateral   : ${m.totalCollateral}</pre>`;
    } catch (e) {
      info.innerHTML = `<span class="status-err">load failed: ${(e as Error).message}</span>`;
    }
  });
}

function bindOrderForm(): void {
  const form = $("order-form") as HTMLFormElement;
  // Default expiry to now + 1 hour.
  (form.elements.namedItem("expiry") as HTMLInputElement).value = String(
    Math.floor(Date.now() / 1000) + 3600,
  );
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const out = $("signed-order-output");
    if (!state.config || !state.walletClient || !state.account) {
      out.textContent = "connect wallet first";
      return;
    }
    const fd = new FormData(form);
    let builder = (fd.get("builder") as string).trim();
    if (!builder) {
      // default to msg.sender's address padded to bytes32 (the contract's claimer convention)
      builder = "0x" + "0".repeat(24) + state.account.slice(2);
    }
    const order = {
      maker: state.account,
      marketId: BigInt(String(fd.get("marketId"))),
      outcome: Number(fd.get("outcome")),
      price: BigInt(String(fd.get("price"))),
      size: BigInt(String(fd.get("size"))),
      feeBps: BigInt(String(fd.get("feeBps"))),
      builder: builder as `0x${string}`,
      salt: BigInt(Math.floor(Math.random() * 1e15)),
      expiry: BigInt(String(fd.get("expiry"))),
    };
    try {
      const signed = await signOrder(state.walletClient, state.config.chainId, state.config.operator, order);
      out.textContent = serializeSignedOrder(signed);
    } catch (e) {
      out.textContent = `sign failed: ${(e as Error).message}`;
    }
  });
}

function bindMatchForm(): void {
  const form = $("match-form") as HTMLFormElement;
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const out = $("match-output");
    if (!state.config || !state.walletClient) {
      out.textContent = "connect wallet first";
      return;
    }
    try {
      const fd = new FormData(form);
      const yesSigned = parseSignedOrder(String(fd.get("yesOrder")));
      const noSigned = parseSignedOrder(String(fd.get("noOrder")));
      const fillSize = BigInt(String(fd.get("fillSize")));
      const hash = await matchOrders(
        state.walletClient,
        state.config.operator,
        yesSigned,
        noSigned,
        fillSize,
      );
      out.textContent = `submitted. tx hash: ${hash}`;
    } catch (e) {
      out.textContent = `match failed: ${(e as Error).message}`;
    }
  });
}

function bindDashboard(): void {
  $("dashboard-refresh").addEventListener("click", () => void renderDashboard());
}

async function renderDashboard(): Promise<void> {
  const out = $("dashboard-output");
  if (!state.config || !state.pub) {
    out.textContent = "save config first";
    return;
  }
  out.textContent = "loading...";
  try {
    const [all, fills] = await Promise.all([
      loadAllMarkets(state.pub, state.config.operator),
      aggregateFills(state.pub, state.config.operator),
    ]);
    const totalCollateral = all.reduce((acc, m) => acc + m.totalCollateral, 0n);
    const byState = STATE_NAMES.map((name, idx) => ({
      name,
      count: all.filter((m) => m.state === idx).length,
    }));

    const decimals = commitmentConfig.settlement_token_decimals;
    const notionalUSD = Number(fills.notional) / 10 ** decimals;
    const tiers = commitmentConfig.tiers;
    const committedTier = commitmentConfig.committed_tier as keyof typeof tiers;
    const target = tiers[committedTier];

    const tierFor = (current: number, metric: "txns" | "notional_usd" | "wallets") => {
      const order: (keyof typeof tiers)[] = ["breakout", "strong", "credible", "minimum"];
      for (const t of order) {
        if (current >= tiers[t][metric]) return t;
      }
      return "below" as const;
    };

    const txnTier = tierFor(fills.fillCount, "txns");
    const notionalTier = tierFor(notionalUSD, "notional_usd");
    const walletsTier = tierFor(fills.uniqueWallets, "wallets");

    const stratLine = (label: string, current: number | string, targetVal: number, tier: string, unit = "") =>
      `  ${label.padEnd(16)} ${String(current).padStart(8)}${unit} / target ${targetVal}${unit} (${tier})`;

    const rows = all.map((m) => {
      const stateName = STATE_NAMES[m.state] ?? "?";
      return `  ${String(m.marketId).padStart(3, " ")}  ${stateName.padEnd(20, " ")} collateral=${m.totalCollateral}  resolver=${m.resolver.slice(0, 10)}…`;
    });

    out.innerHTML = `<pre>day-1 commitment (${committedTier} tier):
${stratLine("txns (fills)", fills.fillCount, target.txns, txnTier)}
${stratLine("notional usd", notionalUSD.toFixed(2), target.notional_usd, notionalTier)}
${stratLine("unique wallets", fills.uniqueWallets, target.wallets, walletsTier)}

markets         : ${all.length}
total collateral: ${totalCollateral}
by state        :
  ${byState.map((s) => `${s.name}=${s.count}`).join("  ")}

per-market:
${rows.join("\n")}</pre>`;
  } catch (e) {
    out.innerHTML = `<span class="status-err">dashboard load failed: ${(e as Error).message}</span>`;
  }
}

function bindRedeemForm(): void {
  const form = $("redeem-form") as HTMLFormElement;
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const out = $("redeem-output");
    if (!state.config || !state.walletClient) {
      out.textContent = "connect wallet first";
      return;
    }
    try {
      const fd = new FormData(form);
      const id = BigInt(String(fd.get("marketId")));
      const hash = await redeem(state.walletClient, state.config.operator, id);
      out.textContent = `submitted. tx hash: ${hash}`;
    } catch (e) {
      out.textContent = `redeem failed: ${(e as Error).message}`;
    }
  });
}

function init(): void {
  renderConfigForm();
  renderWalletBar();
  bindConfigForm();
  bindLoadMarketForm();
  bindOrderForm();
  bindMatchForm();
  bindRedeemForm();
  bindDashboard();
  if (state.config) {
    state.pub = publicClientFor(buildChain(state.config.chainId));
  }
}

init();
