//! # reverb-markets-arc-fs
//!
//! Reverb Markets's tool library. Imported as a Cargo dependency by each persona binary in
//! `agents/reverb-markets-personas`; the persona binary composes its forager via
//! `PersonaForagerBuilder` and picks the subset of `markets_tools(namespace)` it is
//! authorized to call.
//!
//! There is no standalone `reverb-markets-arc-fs` forager process. The forager IS each
//! persona binary, holding its own ed25519 hid + EOA private key + scoped tool list.
//!
//! Spec: <https://reverbprotocol.github.io/protocol/OPERATING_MODEL#cross-product-mesh-conventions>

pub mod chis;
pub mod tools;

pub use chis::MARKETS_CHIS;
pub use tools::{
    create_market, file_dispute, markets_tools, read_market_state, read_settlement_history,
    resolve_market, rule_dispute, subscribe_release_feed, ACTION_CREATE_MARKET,
    ACTION_FILE_DISPUTE, ACTION_READ_MARKET_STATE, ACTION_READ_SETTLEMENT_HISTORY,
    ACTION_RESOLVE_MARKET, ACTION_RULE_DISPUTE, ACTION_SUBSCRIBE_RELEASE_FEED,
};
