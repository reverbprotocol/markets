// SPDX-License-Identifier: Apache-2.0

import type { Address, PublicClient, WalletClient } from "viem";
import { operatorAbi } from "./abi";
import type { SignedOrder } from "./orders";

export const STATE_NAMES = ["Open", "ResolutionProposed", "Disputed", "Settled", "Cancelled"];

export interface MarketView {
  marketId: bigint;
  questionHash: `0x${string}`;
  settlementToken: Address;
  resolver: Address;
  resolutionDeadline: bigint;
  challengeWindowSeconds: number;
  proposedAt: bigint;
  state: number;
  winningOutcome: number;
  totalCollateral: bigint;
}

export async function marketCount(pub: PublicClient, operator: Address): Promise<bigint> {
  return (await pub.readContract({
    address: operator,
    abi: operatorAbi,
    functionName: "marketCount",
  })) as bigint;
}

export async function loadAllMarkets(pub: PublicClient, operator: Address): Promise<MarketView[]> {
  const count = await marketCount(pub, operator);
  const ids = Array.from({ length: Number(count) }, (_, i) => BigInt(i));
  return Promise.all(ids.map((id) => loadMarket(pub, operator, id)));
}

const orderFilledEvent = {
  type: "event",
  name: "OrderFilled",
  inputs: [
    { name: "yesOrderHash", type: "bytes32", indexed: true },
    { name: "noOrderHash", type: "bytes32", indexed: true },
    { name: "marketId", type: "uint256", indexed: true },
    { name: "yesMaker", type: "address" },
    { name: "noMaker", type: "address" },
    { name: "fillSize", type: "uint256" },
    { name: "yesPrice", type: "uint256" },
    { name: "noPrice", type: "uint256" },
    { name: "yesBuilder", type: "bytes32" },
    { name: "noBuilder", type: "bytes32" },
  ],
} as const;

export interface FillStats {
  fillCount: number;
  uniqueWallets: number;
  notional: bigint;
}

export async function aggregateFills(pub: PublicClient, operator: Address): Promise<FillStats> {
  const logs = await pub.getLogs({
    address: operator,
    event: orderFilledEvent,
    fromBlock: 0n,
    toBlock: "latest",
  });
  const wallets = new Set<string>();
  let notional = 0n;
  for (const l of logs) {
    const args = l.args as { yesMaker?: Address; noMaker?: Address; fillSize?: bigint };
    if (args.yesMaker) wallets.add(args.yesMaker.toLowerCase());
    if (args.noMaker) wallets.add(args.noMaker.toLowerCase());
    if (args.fillSize) notional += args.fillSize;
  }
  return { fillCount: logs.length, uniqueWallets: wallets.size, notional };
}

export async function loadMarket(
  pub: PublicClient,
  operator: Address,
  marketId: bigint,
): Promise<MarketView> {
  const m = (await pub.readContract({
    address: operator,
    abi: operatorAbi,
    functionName: "markets",
    args: [marketId],
  })) as readonly [
    `0x${string}`,
    Address,
    Address,
    bigint,
    number,
    bigint,
    number,
    number,
    bigint,
  ];
  return {
    marketId,
    questionHash: m[0],
    settlementToken: m[1],
    resolver: m[2],
    resolutionDeadline: m[3],
    challengeWindowSeconds: m[4],
    proposedAt: m[5],
    state: m[6],
    winningOutcome: m[7],
    totalCollateral: m[8],
  };
}

export async function shareBalance(
  pub: PublicClient,
  operator: Address,
  marketId: bigint,
  holder: Address,
  outcome: number,
): Promise<bigint> {
  return (await pub.readContract({
    address: operator,
    abi: operatorAbi,
    functionName: "shares",
    args: [marketId, holder, outcome],
  })) as bigint;
}

export async function matchOrders(
  walletClient: WalletClient,
  operator: Address,
  yesSigned: SignedOrder,
  noSigned: SignedOrder,
  fillSize: bigint,
): Promise<`0x${string}`> {
  if (!walletClient.account) throw new Error("wallet not connected");
  const hash = await walletClient.writeContract({
    address: operator,
    abi: operatorAbi,
    functionName: "matchOrders",
    args: [yesSigned.order, yesSigned.signature, noSigned.order, noSigned.signature, fillSize],
    account: walletClient.account,
    chain: walletClient.chain,
  });
  return hash;
}

export async function redeem(
  walletClient: WalletClient,
  operator: Address,
  marketId: bigint,
): Promise<`0x${string}`> {
  if (!walletClient.account) throw new Error("wallet not connected");
  return await walletClient.writeContract({
    address: operator,
    abi: operatorAbi,
    functionName: "redeem",
    args: [marketId],
    account: walletClient.account,
    chain: walletClient.chain,
  });
}
