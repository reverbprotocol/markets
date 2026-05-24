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
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts OpenZeppelin/openzeppelin-contracts-upgradeable reverbprotocol/protocol --no-git
forge build
forge test -vv

cd ../auto-resolve
cargo build

cd ../app
npm install
npx tsx scripts/smoke.ts
```

## Security posture

The deployed configuration on Arc testnet (`.deployments/arc-testnet.json`):

- **UUPS upgradeable.** `Operator` is an `Initializable` + `UUPSUpgradeable` contract behind an ERC1967 proxy. Inherits the upgrade-safe `CCTPReceiverMixin` from `reverbprotocol/protocol` (ERC-7201 namespaced storage so the mixin's slots never collide with the Operator layout).
- **TimelockController owns upgrade authority.** Same TimelockController as the substrate (shared on testnet per the deployments file). 24-hour delay on every upgrade; visible on-chain during the delay window.
- **Safe multisig fronts the TimelockController.** Same 3-of-5 Safe as the substrate. Sole proposer + executor on the TimelockController.
- **Pausable critical paths.** `matchOrders`, `proposeResolution`, `challengeResolution` are gated by `whenNotPaused`. `pause()` is callable by the `pauser` (Safe directly). `unpause()` is `onlyOwner` (Timelock-gated). `settle`, `redeem`, `withdrawBuilderFees` remain live during pause so existing market lifecycles complete.
- **Reentrancy.** `ReentrancyGuardTransient` on every state-mutating external function.
- **Selector + event freeze tests.** `contracts/test/SelectorFreezeOperator.t.sol` locks 11 external function selectors (including the inherited `onCCTPReceive`) and 10 event topic hashes.
- **Stateful fuzz invariants.** `contracts/test/OperatorInvariant.t.sol` runs 256 fuzz runs asserting initializer-only-once and owner-remains-Timelock under randomized createMarket activity.
- **Slither static analysis.** `.github/workflows/security.yml` runs Slither on every PR with `fail-on=high`. Mythril runs nightly.

## License

Apache-2.0.
