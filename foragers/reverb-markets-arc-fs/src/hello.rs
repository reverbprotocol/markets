//! Reverb Markets hello manifest: extends the base `reverb-arc-fs` hello with the
//! product-specific chi vocabulary and tools.

use reverb_arc_fs::manifest::Hello;

/// Reverb Markets-specific chis added on top of the base vocabulary.
pub const MARKETS_CHIS: &[&str] = &[
    "market-created",
    "market-resolved",
    "dispute-filed",
    "dispute-ruled",
    "settlement-completed",
];

/// Reverb Markets-specific tool surface composed on top of `arc_send_tx` / `arc_read_state`.
pub const MARKETS_TOOLS: &[&str] = &[
    "markets_create_market",
    "markets_resolve_market",
    "markets_file_dispute",
    "markets_rule_dispute",
    "markets_read_market_state",
    "markets_read_settlement_history",
    "markets_subscribe_release_feed",
];

/// Build the hello manifest emitted on attach. Extends the base forager's hello with this
/// product's chis and tools.
pub fn manifest() -> Hello {
    Hello::base("reverb-markets-arc-fs", "0.1.0")
        .with_wire("reverb-markets/arc-fs")
        .with_source(
            "https://github.com/reverbprotocol/markets/tree/main/foragers/reverb-markets-arc-fs",
        )
        .extend(
            MARKETS_CHIS.iter().map(|s| s.to_string()),
            MARKETS_TOOLS.iter().map(|s| s.to_string()),
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_carries_both_base_and_product_surface() {
        let h = manifest();
        assert_eq!(h.bee, "reverb-markets-arc-fs");
        assert_eq!(h.propensity.wire, "reverb-markets/arc-fs");
        // Base tool from reverb-arc-fs
        assert!(h.tools.contains(&"arc_send_tx".to_string()));
        // Product-specific tool
        assert!(h.tools.contains(&"markets_create_market".to_string()));
        // Base chi
        assert!(h.chis.contains(&"tool-call".to_string()));
        // Product-specific chi
        assert!(h.chis.contains(&"dispute-filed".to_string()));
    }

    #[test]
    fn manifest_serializes_to_camelcase_proto_version() {
        let h = manifest();
        let json = serde_json::to_string(&h).unwrap();
        assert!(json.contains("\"protoVersion\":\"0.7.0\""));
        assert!(json.contains("\"wire\":\"reverb-markets/arc-fs\""));
    }
}
