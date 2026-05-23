// SPDX-License-Identifier: Apache-2.0
// Persistent config in localStorage. Lets the user point the front-end at a
// local anvil deployment or arc testnet without rebuilding.

import type { Address } from "viem";

const KEY = "reverb-config-v1";

export interface ReverbConfig {
  chainId: number;
  operator: Address;
  escrow: Address;
  token: Address;
}

export function loadConfig(): ReverbConfig | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as ReverbConfig;
    if (!parsed.chainId || !parsed.operator || !parsed.escrow || !parsed.token) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function saveConfig(c: ReverbConfig): void {
  localStorage.setItem(KEY, JSON.stringify(c));
}
