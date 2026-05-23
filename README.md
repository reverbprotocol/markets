# Reverb Markets

Reverb Markets is a third-party prediction-market operator on Arc. EIP-712 signed orderbook with per-fill `bytes32` builder attribution. Extracted from project-reverb on 2026-05-23 alongside the substrate at `reverbprotocol/protocol`. A second product, Daman, ships on the same substrate at daman.fi.

## Lineage and citations

- Operator substrate forked from the project-reverb `apps/dispute-escrow/` workspace; dispute primitive imported as a Foundry dependency from `reverbprotocol/protocol`.
- Bug-fix dossier: `RefundProtocolFixed` cherry-picks four classes of correctness fix against `circlefin/refund-protocol@b506b17` (CEI on `_executeRefund`, cumulative over-withdraw guard, debt-settle-before-early-withdraw, zero-recipient guard). See `reverbprotocol/protocol/CHANGELOG.md`.
- Intellectual lineage: Canteen 2026-05-01 "Unbundling the Prediction Market Stack" (https://thecanteenapp.com/analysis/2026/05/01/unbundling-the-prediction-market-stack.html); Tauric Research multi-agent trading framework (arXiv 2412.20138); `circlefin/arc-escrow` reference integration.

## Layout

| Path | Purpose |
|---|---|
| `contracts/src/Operator.sol` | EIP-712 binary-market operator with builder-bytes32 attribution per fill. |
| `contracts/test/Operator.t.sol` | Operator test suite. |
| `contracts/script/DeployOperator.s.sol` | Deploys Operator against an existing `RefundProtocolFixed`. |
| `contracts/script/DeployLocal.s.sol` | One-shot local deployment for demo and front-end smoke. |
| `auto-resolve/` | Rust daemon polling BLS / FRED / Census release feeds and dispatching signed resolution claims. |
| `app/` | TypeScript five-panel storefront. Builder-code attribution, multi-currency display, dashboard. |
| `scripts/` | Local development scripts (anvil + auto-resolve + app boot). |
| `marketing/submission-video.md` | Submission video script per `apps/marketing/`. |

## Build

```bash
cd contracts
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts reverbprotocol/protocol --no-git
# rename lib/protocol/src/ resolves; the install creates lib/protocol/
forge build
forge test -vv

cd ../auto-resolve
cargo build

cd ../app
npm install
npx tsx scripts/smoke.ts
```

## License

Apache-2.0.
