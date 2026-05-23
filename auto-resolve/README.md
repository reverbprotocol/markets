# auto-resolve

Resolver daemon for the project-reverb operator. Polls macro-data releases (BLS, FRED, Census), maps each release to a YES/NO outcome against an off-chain market registry, and submits a signed resolution proposal to the operator contract.

This crate is published as the **reference resolver implementation** for any third-party agent operating against the operator. Apache-2.0. Fork it, extend the feed adapters, plug in your own data sources. The on-chain interface (`proposeResolution(uint256,uint8)` plus the EIP-712 signing convention) is the contract; everything else is a starting point.

## Build

```
cargo build --release
```

## Run

One-shot resolution of a single market:

```
cargo run -- once --market-id 0
```

Continuous loop:

```
cargo run -- watch --interval-secs 60
```

## Configuration

Required environment:

- `RESOLVER_PRIVATE_KEY` (hex, no 0x prefix accepted by alloy directly; with-prefix is normalized) — the resolver signing key. Stored in `~/.reverb/operator-resolver.key` per the credential convention; the wrapper script `scripts/run.sh` sources from there.
- `RPC_URL` — Arc testnet (or local anvil) JSON-RPC.
- `OPERATOR_ADDRESS` — deployed `Operator` contract address.

Optional:

- `FRED_API_KEY` — only required for FRED-backed series. BLS series work keyless under the public 25-req/day rate. If unset, FRED-backed markets skip with a warning.
- `REGISTRY_PATH` — defaults to `./registry/markets.json`.
- `RUST_LOG` — defaults to `auto_resolve=info`.

## Registry format

`registry/markets.json` maps an on-chain `marketId` to the off-chain question metadata. Format documented in `src/registry.rs`. Each entry names the feed, the series id, the release date the resolver should look for, the threshold the question turns on, and the comparison operator that produces YES.

## Constraints

- Resolver only proposes after `resolutionDeadline` per the operator contract; calls before that revert and the daemon logs and skips.
- Resolver does not bypass the on-chain challenge window. Once `proposeResolution` lands, settlement is on the operator's clock, not the daemon's.
- All HTTP fetches go through `reqwest` with rustls. No native-tls dependency, no system OpenSSL coupling.

## Historical replay

Each resolver decision is reproducible from inputs. To verify the reference decision (deterministic, no network):

```
cargo test parser::tests::replay
```

The test fixture asserts: given the observed CPI YoY% recorded by the live-network smoke test on 2026-05-10 (`3.2564…`) against threshold `3.2` with comparison `gt`, the parser derives outcome `0`. The same logic runs against live BLS data in production. A fresh agent cloning this repo and running the test should see the same outcome on the same inputs; that determinism is the load-bearing property of the reference implementation.

## License

Apache-2.0. See `LICENSE`.
