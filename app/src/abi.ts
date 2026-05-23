// SPDX-License-Identifier: Apache-2.0
// Minimal ABIs for the Operator and RefundProtocolFixed contracts.
// Hand-curated. Only the methods and events the front-end calls.

export const operatorAbi = [
  {
    type: "function",
    name: "marketCount",
    inputs: [],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "markets",
    inputs: [{ type: "uint256" }],
    outputs: [
      { name: "questionHash", type: "bytes32" },
      { name: "settlementToken", type: "address" },
      { name: "resolver", type: "address" },
      { name: "resolutionDeadline", type: "uint64" },
      { name: "challengeWindowSeconds", type: "uint32" },
      { name: "proposedAt", type: "uint64" },
      { name: "state", type: "uint8" },
      { name: "winningOutcome", type: "uint8" },
      { name: "totalCollateral", type: "uint256" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "shares",
    inputs: [
      { type: "uint256" },
      { type: "address" },
      { type: "uint8" },
    ],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "matchOrders",
    inputs: [
      {
        name: "yesOrder",
        type: "tuple",
        components: [
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
      },
      { name: "yesSig", type: "bytes" },
      {
        name: "noOrder",
        type: "tuple",
        components: [
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
      },
      { name: "noSig", type: "bytes" },
      { name: "fillSize", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "redeem",
    inputs: [{ type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "DOMAIN_SEPARATOR",
    inputs: [],
    outputs: [{ type: "bytes32" }],
    stateMutability: "view",
  },
] as const;

export const erc20Abi = [
  {
    type: "function",
    name: "approve",
    inputs: [
      { type: "address" },
      { type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ type: "address" }],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "allowance",
    inputs: [
      { type: "address" },
      { type: "address" },
    ],
    outputs: [{ type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "decimals",
    inputs: [],
    outputs: [{ type: "uint8" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "symbol",
    inputs: [],
    outputs: [{ type: "string" }],
    stateMutability: "view",
  },
] as const;
