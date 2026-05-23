// SPDX-License-Identifier: Apache-2.0
//
// End-to-end smoke test for the dispute flow.
//
// Flow:
//   1. (assumes start-local.sh has been run; assumes orders smoke has run so
//      market 0 has 1M collateral)
//   2. time-warp anvil past resolutionDeadline
//   3. resolver/admin proposes outcome 0 (YES)
//   4. challenger (carol) approves USDC, calls challengeResolution → bond
//      escrowed in RefundProtocolFixed
//   5. arbiter (deployer) finalizes against the challenger, then issues
//      refundByArbiter on the escrow → bond returns to treasury
//   6. settle the market on the operator
//   7. winning holder (alice, YES) redeems → 1M MockUSDC
//
// Usage:
//   cd apps/web
//   npx tsx scripts/smoke-dispute.ts

import { readFileSync } from "node:fs";
import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  parseUnits,
} from "viem";
import type { Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { operatorAbi, erc20Abi } from "../src/abi.ts";

const ANVIL_KEYS = {
  alice: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as `0x${string}`,
  carol: "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a" as `0x${string}`,
};

const RPC_URL = "http://127.0.0.1:8545";
const anvil = defineChain({
  id: 31337,
  name: "anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
});

const refundEscrowAbi = [
  {
    type: "function",
    name: "refundByArbiter",
    inputs: [{ type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "balances",
    inputs: [{ type: "address" }],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
] as const;

const operatorExtAbi = [
  ...operatorAbi,
  {
    type: "function",
    name: "proposeResolution",
    inputs: [
      { type: "uint256" },
      { type: "uint8" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "challengeResolution",
    inputs: [{ type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "arbiterFinalizeDispute",
    inputs: [
      { type: "uint256" },
      { type: "uint8" },
      { type: "bool" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "settle",
    inputs: [{ type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "disputePaymentId",
    inputs: [{ type: "uint256" }],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "challengeBond",
    inputs: [],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
] as const;

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

async function evmRpc(method: string, params: unknown[] = []): Promise<unknown> {
  const r = await fetch(RPC_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const j = (await r.json()) as { result?: unknown; error?: { message: string } };
  if (j.error) throw new Error(`${method}: ${j.error.message}`);
  return j.result;
}

async function main(): Promise<void> {
  const addrs = readAddresses();
  console.log("addresses:", addrs);

  const pub = createPublicClient({ chain: anvil, transport: http(RPC_URL) });
  const aliceAcct = privateKeyToAccount(ANVIL_KEYS.alice);
  const carolAcct = privateKeyToAccount(ANVIL_KEYS.carol);
  const aliceWallet = createWalletClient({ account: aliceAcct, chain: anvil, transport: http(RPC_URL) });
  const carolWallet = createWalletClient({ account: carolAcct, chain: anvil, transport: http(RPC_URL) });

  // Step 1: time-warp past resolutionDeadline (script set deadline = block.timestamp + 1h)
  console.log("\n[1/7] time-warping anvil 4000 seconds (~67 min) and mining...");
  await evmRpc("evm_increaseTime", [4000]);
  await evmRpc("evm_mine");

  // Step 2: deployer/resolver proposes outcome 0
  console.log("[2/7] alice (resolver) calls proposeResolution(0, 0)...");
  const tx2 = await aliceWallet.writeContract({
    address: addrs.operator,
    abi: operatorExtAbi,
    functionName: "proposeResolution",
    args: [0n, 0],
  });
  await pub.waitForTransactionReceipt({ hash: tx2 });

  // Step 3: carol approves + challenges
  console.log("[3/7] carol approves USDC and challenges resolution...");
  const bond = (await pub.readContract({
    address: addrs.operator,
    abi: operatorExtAbi,
    functionName: "challengeBond",
  })) as bigint;
  console.log("    challenge bond:", bond);

  // Need to mint carol some USDC first; she may not have enough. Mint her bond + slack.
  const mintTx = await aliceWallet.writeContract({
    address: addrs.usdc,
    abi: [{ type: "function", name: "mint", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [], stateMutability: "nonpayable" }],
    functionName: "mint",
    args: [carolAcct.address, bond * 2n],
  });
  await pub.waitForTransactionReceipt({ hash: mintTx });

  const approveTx = await carolWallet.writeContract({
    address: addrs.usdc,
    abi: erc20Abi,
    functionName: "approve",
    args: [addrs.operator, bond],
  });
  await pub.waitForTransactionReceipt({ hash: approveTx });

  const challTx = await carolWallet.writeContract({
    address: addrs.operator,
    abi: operatorExtAbi,
    functionName: "challengeResolution",
    args: [0n],
  });
  await pub.waitForTransactionReceipt({ hash: challTx });

  // Step 4: read disputePaymentId
  const paymentId = (await pub.readContract({
    address: addrs.operator,
    abi: operatorExtAbi,
    functionName: "disputePaymentId",
    args: [0n],
  })) as bigint;
  console.log("    dispute payment id in escrow:", paymentId);

  // Step 5: arbiter (alice = deployer) finalizes against the challenger AND refunds the bond
  console.log("[4/7] alice (arbiter) finalizes dispute against challenger and refunds bond...");
  const finalTx = await aliceWallet.writeContract({
    address: addrs.operator,
    abi: operatorExtAbi,
    functionName: "arbiterFinalizeDispute",
    args: [0n, 0, false], // resolution stands (outcome 0), challenger lost
  });
  await pub.waitForTransactionReceipt({ hash: finalTx });
  const refundTx = await aliceWallet.writeContract({
    address: addrs.escrow,
    abi: refundEscrowAbi,
    functionName: "refundByArbiter",
    args: [paymentId],
  });
  await pub.waitForTransactionReceipt({ hash: refundTx });

  // Step 6: market is already Settled (arbiterFinalizeDispute did that)
  console.log("[5/7] market state after arbiter:");
  const m = (await pub.readContract({
    address: addrs.operator,
    abi: operatorExtAbi,
    functionName: "markets",
    args: [0n],
  })) as readonly unknown[];
  console.log("    state           :", m[6], "(4=Cancelled, 3=Settled)");
  console.log("    winningOutcome  :", m[7]);
  console.log("    totalCollateral :", m[8]);

  // Step 7: alice redeems her YES shares
  console.log("[6/7] alice redeems winning shares...");
  const aliceUSDCBefore = (await pub.readContract({
    address: addrs.usdc,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [aliceAcct.address],
  })) as bigint;
  const redeemTx = await aliceWallet.writeContract({
    address: addrs.operator,
    abi: operatorExtAbi,
    functionName: "redeem",
    args: [0n],
  });
  await pub.waitForTransactionReceipt({ hash: redeemTx });
  const aliceUSDCAfter = (await pub.readContract({
    address: addrs.usdc,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [aliceAcct.address],
  })) as bigint;
  const won = aliceUSDCAfter - aliceUSDCBefore;
  console.log("    alice received:", won, "(should be 1000000 = 1M units = 1 MockUSDC)");
  if (won !== parseUnits("1", 6)) throw new Error(`expected 1 USDC payout, got ${won}`);

  console.log("\n[7/7] dispute flow end-to-end green:");
  console.log("      propose -> challenge -> arbiter rule -> bond returned to treasury -> settle -> redeem");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
