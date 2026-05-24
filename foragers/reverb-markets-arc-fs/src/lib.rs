//! # reverb-markets-arc-fs
//!
//! Reverb Markets's forager hive extending `reverb-arc-fs` with seven product-specific tools.
//! Imports the base forager's keyring + safety pipeline; adds high-level tools that
//! internally compose `arc_send_tx` / `arc_read_state` against the Reverb Markets contracts.
//!
//! Spec: <https://reverbprotocol.github.io/protocol/OPERATING_MODEL#cross-product-mesh-conventions>

pub mod hello;
pub mod tools;

pub use hello::manifest;
