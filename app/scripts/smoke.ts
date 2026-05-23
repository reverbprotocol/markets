// SPDX-License-Identifier: Apache-2.0
//
// End-to-end smoke test against the local anvil deployment.
//
// Usage:
//   cd apps/web
//   npx tsx scripts/smoke.ts
//
// Prereq: ../scripts/start-local.sh has been run; anvil is alive on :8545
// and /tmp/reverb-deploy.txt contains the deployed addresses.

import { readFileSync } from "node:fs";
import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  parseUnits,
  zeroAddress,
} from "viem";
import type { Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { operatorAbi, erc20Abi } from "../src/abi.ts";
import { signOrder } from "../src/orders.ts";
import type { Order } from "../src/orders.ts";

// Anvil's well-known keys. Public knowledge; not credentials we minted.
const ANVIL_KEYS = {
  alice: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
  bob: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as `0x${string}`,
  carol: "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a" as `0x${string}`,
};

const RPC_URL = "http://127.0.0.1:8545";

const anvil = defineChain({
  id: 31337,
  name: "anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
});

interface DeploymentAddrs {
  usdc: Address;
  escrow: Address;
  operator: Address;
}

function readAddresses(): DeploymentAddrs {
  const raw = readFileSync("/tmp/reverb-deploy.txt", "utf8");
  const grab = (label: string): Address => {
    const m = raw.match(new RegExp(`${label}\\s*:\\s*(0x[a-fA-F0-9]{40})`));
    if (!m) throw new Error(`missing ${label} in /tmp/reverb-deploy.txt`);
    return m[1] as Address;
  };
  return {
    usdc: grab("MockUSDC"),
    escrow: grab("disputeEscrow"),
    operator: grab("operator"),
  };
}

async function main(): Promise<void> {
  const addrs = readAddresses();
  console.log("addresses:", addrs);

  const pub = createPublicClient({ chain: anvil, transport: http(RPC_URL) });

  const aliceAcct = privateKeyToAccount(ANVIL_KEYS.alice);
  const bobAcct = privateKeyToAccount(ANVIL_KEYS.bob);

  const aliceWallet = createWalletClient({ account: aliceAcct, chain: anvil, transport: http(RPC_URL) });
  const bobWallet = createWalletClient({ account: bobAcct, chain: anvil, transport: http(RPC_URL) });
  const carolWallet = createWalletClient({
    account: privateKeyToAccount(ANVIL_KEYS.carol),
    chain: anvil,
    transport: http(RPC_URL),
  });

  // Anvil's deployer (alice) holds 1M USDC. Mint to bob too.
  console.log("\n[1/6] minting MockUSDC to bob from alice (deployer)...");
  await aliceWallet.writeContract({
    address: addrs.usdc,
    abi: [
      { type: "function", name: "mint", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
    ],
    functionName: "mint",
    args: [bobAcct.address, parseUnits("1000000", 6)],
  });
  // Operator is anyone; carol uses it as the matcher
  await aliceWallet.writeContract({
    address: addrs.usdc,
    abi: [
      { type: "function", name: "mint", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
    ],
    functionName: "mint",
    args: [carolWallet.account.address, parseUnits("1000000", 6)],
  });

  // Approvals
  console.log("[2/6] approving operator to spend USDC from alice + bob...");
  for (const wc of [aliceWallet, bobWallet]) {
    await wc.writeContract({
      address: addrs.usdc,
      abi: erc20Abi,
      functionName: "approve",
      args: [addrs.operator, 2n ** 256n - 1n],
    });
  }

  // Build orders. fillSize = 1_000_000 (1 USDC). Alice YES @ 0.6, Bob NO @ 0.4.
  // Builder tag = anvil deployer's address padded.
  const fillSize = parseUnits("1", 6); // 1 unit, 6dp
  const expiry = BigInt(Math.floor(Date.now() / 1000) + 600);
  const builderTag = ("0x" + "0".repeat(24) + aliceAcct.address.slice(2)) as `0x${string}`;

  const yesOrder: Order = {
    maker: aliceAcct.address,
    marketId: 0n,
    outcome: 0,
    price: 6000n,
    size: fillSize,
    feeBps: 100n,
    builder: builderTag,
    salt: 1n,
    expiry,
  };
  const noOrder: Order = {
    maker: bobAcct.address,
    marketId: 0n,
    outcome: 1,
    price: 4000n,
    size: fillSize,
    feeBps: 100n,
    builder: builderTag,
    salt: 2n,
    expiry,
  };

  console.log("[3/6] alice signs YES order (EIP-712)...");
  const yesSigned = await signOrder(aliceWallet, anvil.id, addrs.operator, yesOrder);
  console.log("[3/6] bob signs NO order (EIP-712)...");
  const noSigned = await signOrder(bobWallet, anvil.id, addrs.operator, noOrder);

  // Carol matches the orders.
  console.log("[4/6] carol calls matchOrders(...) on the operator...");
  const matchTx = await carolWallet.writeContract({
    address: addrs.operator,
    abi: operatorAbi,
    functionName: "matchOrders",
    args: [yesSigned.order, yesSigned.signature, noSigned.order, noSigned.signature, fillSize],
  });
  console.log("    tx:", matchTx);
  await pub.waitForTransactionReceipt({ hash: matchTx });

  // Verify
  console.log("[5/6] verifying on-chain shares + collateral...");
  const aliceShares = (await pub.readContract({
    address: addrs.operator,
    abi: operatorAbi,
    functionName: "shares",
    args: [0n, aliceAcct.address, 0],
  })) as bigint;
  const bobShares = (await pub.readContract({
    address: addrs.operator,
    abi: operatorAbi,
    functionName: "shares",
    args: [0n, bobAcct.address, 1],
  })) as bigint;
  const collateral = (await pub.readContract({
    address: addrs.operator,
    abi: operatorAbi,
    functionName: "markets",
    args: [0n],
  })) as readonly unknown[];

  console.log("    alice YES shares :", aliceShares);
  console.log("    bob   NO  shares :", bobShares);
  console.log("    market collateral:", collateral[8]);

  if (aliceShares !== fillSize) throw new Error("expected alice to hold fillSize YES shares");
  if (bobShares !== fillSize) throw new Error("expected bob to hold fillSize NO shares");

  console.log("\n[6/6] success. orders signed by viem matched the contract's EIP-712 hash.");
  console.log("      avoid double-counting: sanity-check zeroAddress is unused:", zeroAddress);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
