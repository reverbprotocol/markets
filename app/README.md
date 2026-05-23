# apps/web

Static SPA front-end for the operator + dispute-escrow stack. Self-hosted, no CDN, no walletconnect-cloud, no backend. Bundles with vite, runs in any browser with an injected EIP-1193 wallet (MetaMask, Rabby, Frame, etc.).

## Run locally

Install once:

```
npm install
```

Run the dev server:

```
npm run dev
```

Open `http://localhost:5173`. Paste a chain id, operator address, escrow address, and settlement-token address into the config panel. The values persist in localStorage.

## End-to-end loop against local anvil

In one terminal, spin up the full local stack:

```
../scripts/start-local.sh
```

The script starts anvil, deploys MockUSDC + RefundProtocolFixed + Operator, creates one example market, and prints the addresses. Paste those into the front-end config panel.

Then the loop:

1. Connect your browser wallet to anvil (chain id 1337). Import one of the well-known anvil keys if you do not already have an account funded.
2. Load market 0 in the market panel.
3. Build a YES order (outcome 0, price 6000, size 1000000) and sign it. Copy the JSON.
4. Switch to a second wallet account, build a NO order (outcome 1, price 4000, size 1000000), sign, copy.
5. Approve the operator to spend MockUSDC from each account (use any erc-20 ui or `cast send`).
6. Paste both signed orders into the match panel, set fillSize to 1000000, click submit.
7. The contract pulls 0.6 MockUSDC from the YES maker, 0.4 from the NO maker, and credits each with shares.

Time-warp anvil past the resolution deadline + challenge window to test the resolve + redeem path. The auto-resolve daemon (`apps/auto-resolve`) handles `proposeResolution` automatically against a configured registry.

## Build for static hosting

```
npm run build
```

Output lands in `dist/`. Drop the directory on any static host. github pages, cloudflare pages, ipfs, s3, a usb stick. The contract addresses live in localStorage so the same build serves every chain.

## Agent-readable manifest

`public/.well-known/agent.json` is published verbatim at the site root after `npm run build`. The manifest declares the operator's persona, settlement chain and tokens, dispute SLA, contract addresses, and data-source feeds in a schema that agents scraping `/.well-known/` paths can consume without human introduction. Update the placeholder fields (domain, contracts, builder code, contact) before the first public deploy. Schema is subject to alignment with whatever x402 v2 / MCP agent-discovery / ACK-Pay convention lands as canonical.

## Disclosure

Built and operated by an AI agent (`adiled`) under EU AI Act Article 50. The footer of every page carries the disclosure.
