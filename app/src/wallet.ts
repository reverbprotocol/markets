// SPDX-License-Identifier: Apache-2.0
// Wallet connect via browser-injected EIP-1193 provider (MetaMask, Rabby, etc).
// No wallet-connect, no walletconnect-cloud project id. Fully self-hosted.

import { createPublicClient, createWalletClient, custom, http } from "viem";
import type { Address, Chain, PublicClient, WalletClient } from "viem";

declare global {
  interface Window {
    ethereum?: {
      request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
      on?: (event: string, handler: (...args: unknown[]) => void) => void;
    };
  }
}

export interface ChainConfig {
  chain: Chain;
  rpcUrl: string;
}

export function buildChain(chainId: number): ChainConfig {
  const rpcUrl = chainId === 31337
    ? "http://127.0.0.1:8545"
    : chainId === 5042002
      ? "https://rpc.quicknode.testnet.arc.network/"
      : "";
  return {
    rpcUrl,
    chain: {
      id: chainId,
      name: chainNameFor(chainId),
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: { default: { http: [rpcUrl] }, public: { http: [rpcUrl] } },
    },
  };
}

function chainNameFor(id: number): string {
  switch (id) {
    case 1: return "ethereum";
    case 31337: return "anvil-local";
    case 5042: return "arc-mainnet";
    case 5042001: return "arc-devnet";
    case 5042002: return "arc-testnet";
    default: return `chain-${id}`;
  }
}

export function publicClientFor(cfg: ChainConfig): PublicClient {
  return createPublicClient({ chain: cfg.chain, transport: http(cfg.rpcUrl) });
}

export async function connectWallet(cfg: ChainConfig): Promise<{ address: Address; walletClient: WalletClient }> {
  if (!window.ethereum) {
    throw new Error("no injected wallet found. install metamask or rabby.");
  }
  const accounts = (await window.ethereum.request({ method: "eth_requestAccounts" })) as Address[];
  if (!accounts.length) throw new Error("no account returned by wallet");

  const walletClient = createWalletClient({
    account: accounts[0],
    chain: cfg.chain,
    transport: custom(window.ethereum),
  });
  return { address: accounts[0], walletClient };
}
