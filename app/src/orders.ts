// SPDX-License-Identifier: Apache-2.0
// EIP-712 order construction + signing. Mirrors the Operator contract's ORDER_TYPEHASH.

import type { Address, WalletClient } from "viem";

export interface Order {
  maker: Address;
  marketId: bigint;
  outcome: number;
  price: bigint;
  size: bigint;
  feeBps: bigint;
  builder: `0x${string}`;
  salt: bigint;
  expiry: bigint;
}

export interface SignedOrder {
  order: Order;
  signature: `0x${string}`;
  domain: {
    chainId: number;
    verifyingContract: Address;
  };
}

const TYPES = {
  Order: [
    { name: "maker", type: "address" },
    { name: "marketId", type: "uint256" },
    { name: "outcome", type: "uint8" },
    { name: "price", type: "uint256" },
    { name: "size", type: "uint256" },
    { name: "feeBps", type: "uint256" },
    { name: "builder", type: "bytes32" },
    { name: "salt", type: "uint256" },
    { name: "expiry", type: "uint256" },
  ],
} as const;

export async function signOrder(
  walletClient: WalletClient,
  chainId: number,
  operator: Address,
  order: Order,
): Promise<SignedOrder> {
  const signature = (await walletClient.signTypedData({
    account: order.maker,
    domain: {
      name: "Operator",
      version: "1",
      chainId,
      verifyingContract: operator,
    },
    types: TYPES,
    primaryType: "Order",
    message: order,
  })) as `0x${string}`;

  return {
    order,
    signature,
    domain: { chainId, verifyingContract: operator },
  };
}

export function serializeSignedOrder(s: SignedOrder): string {
  return JSON.stringify(
    {
      order: {
        maker: s.order.maker,
        marketId: s.order.marketId.toString(),
        outcome: s.order.outcome,
        price: s.order.price.toString(),
        size: s.order.size.toString(),
        feeBps: s.order.feeBps.toString(),
        builder: s.order.builder,
        salt: s.order.salt.toString(),
        expiry: s.order.expiry.toString(),
      },
      signature: s.signature,
      domain: s.domain,
    },
    null,
    2,
  );
}

export function parseSignedOrder(raw: string): SignedOrder {
  const parsed = JSON.parse(raw);
  return {
    order: {
      maker: parsed.order.maker,
      marketId: BigInt(parsed.order.marketId),
      outcome: Number(parsed.order.outcome),
      price: BigInt(parsed.order.price),
      size: BigInt(parsed.order.size),
      feeBps: BigInt(parsed.order.feeBps),
      builder: parsed.order.builder,
      salt: BigInt(parsed.order.salt),
      expiry: BigInt(parsed.order.expiry),
    },
    signature: parsed.signature,
    domain: parsed.domain,
  };
}
