//! Reverb Markets product-specific tool factories. Each function returns a `Tool` with the
//! supplied namespace prefix on its name (e.g. `mkac_create_market` for namespace `mkac`).
//!
//! The forager-as-library pattern: each persona binary picks the subset of these tools it
//! is authorized to call and passes them into `PersonaForagerBuilder::with_tools(...)`.
//! Role enforcement is via the persona's tool list, not via per-call auth: a tool that the
//! persona did not register cannot be invoked through that persona's forager process.
//!
//! All handlers here are wire-shape scaffolds that echo their args. The runtime that spawns
//! the persona binary supplies the concrete sender + simulation gate via the substrate's
//! safety pipeline, which encodes calldata against the Reverb Markets `Operator` contract.

use reverb_arc_fs::tools::{Idempotency, Tool, ToolResult};
use serde_json::json;

/// Action names. The forager exposes them as `<ns>_<action>`; the contract method is the
/// same regardless of namespace (multiple personas with different namespaces call the same
/// underlying chain method).
pub const ACTION_CREATE_MARKET: &str = "create_market";
pub const ACTION_RESOLVE_MARKET: &str = "resolve_market";
pub const ACTION_FILE_DISPUTE: &str = "file_dispute";
pub const ACTION_RULE_DISPUTE: &str = "rule_dispute";
pub const ACTION_READ_MARKET_STATE: &str = "read_market_state";
pub const ACTION_READ_SETTLEMENT_HISTORY: &str = "read_settlement_history";
pub const ACTION_SUBSCRIBE_RELEASE_FEED: &str = "subscribe_release_feed";

/// Convenience: every action this product knows about, namespaced for the given persona.
/// Most persona binaries use a subset; this is the all-in factory for cases that want it.
pub fn markets_tools(namespace: &str) -> Vec<Tool> {
    vec![
        create_market(namespace),
        resolve_market(namespace),
        file_dispute(namespace),
        rule_dispute(namespace),
        read_market_state(namespace),
        read_settlement_history(namespace),
        subscribe_release_feed(namespace),
    ]
}

fn scaffold(tool_name: String, idem: Idempotency) -> Tool {
    let label = tool_name.clone();
    Tool::new(tool_name, idem, move |call| {
        let label = label.clone();
        async move {
            ToolResult::ok(
                call.call_id,
                json!({
                    "tool": label,
                    "status": "scaffold",
                    "args": call.args,
                }),
            )
        }
    })
}

/// `<ns>_create_market`: post a new forward-looking macro market.
pub fn create_market(ns: &str) -> Tool {
    scaffold(format!("{ns}_{ACTION_CREATE_MARKET}"), Idempotency::NotIdempotent)
}

/// `<ns>_resolve_market`: settle a market against a release feed.
pub fn resolve_market(ns: &str) -> Tool {
    scaffold(format!("{ns}_{ACTION_RESOLVE_MARKET}"), Idempotency::NotIdempotent)
}

/// `<ns>_file_dispute`: challenge a resolution via `RefundProtocolFixed`.
pub fn file_dispute(ns: &str) -> Tool {
    scaffold(format!("{ns}_{ACTION_FILE_DISPUTE}"), Idempotency::NotIdempotent)
}

/// `<ns>_rule_dispute`: arbiter ruling on a contested resolution.
pub fn rule_dispute(ns: &str) -> Tool {
    scaffold(format!("{ns}_{ACTION_RULE_DISPUTE}"), Idempotency::NotIdempotent)
}

/// `<ns>_read_market_state`: view current state of any market (read-only).
pub fn read_market_state(ns: &str) -> Tool {
    scaffold(format!("{ns}_{ACTION_READ_MARKET_STATE}"), Idempotency::Idempotent)
}

/// `<ns>_read_settlement_history`: past settlements for analysis (read-only).
pub fn read_settlement_history(ns: &str) -> Tool {
    scaffold(format!("{ns}_{ACTION_READ_SETTLEMENT_HISTORY}"), Idempotency::Idempotent)
}

/// `<ns>_subscribe_release_feed`: external HTTP polling hook wired to humd;
/// emits `chi:release-data` tones on the subscribed sigil.
pub fn subscribe_release_feed(ns: &str) -> Tool {
    scaffold(format!("{ns}_{ACTION_SUBSCRIBE_RELEASE_FEED}"), Idempotency::Idempotent)
}

#[cfg(test)]
mod tests {
    use super::*;
    use reverb_arc_fs::tools::{ToolCall, ToolRegistry};

    #[test]
    fn markets_tools_returns_seven_namespaced_tools() {
        let tools = markets_tools("mkac");
        assert_eq!(tools.len(), 7);
        let names: Vec<_> = tools.iter().map(|t| t.name().to_string()).collect();
        for action in [
            ACTION_CREATE_MARKET,
            ACTION_RESOLVE_MARKET,
            ACTION_FILE_DISPUTE,
            ACTION_RULE_DISPUTE,
            ACTION_READ_MARKET_STATE,
            ACTION_READ_SETTLEMENT_HISTORY,
            ACTION_SUBSCRIBE_RELEASE_FEED,
        ] {
            assert!(names.contains(&format!("mkac_{action}")), "missing mkac_{action}");
        }
    }

    #[test]
    fn different_namespaces_yield_different_tool_names() {
        let mkac = markets_tools("mkac");
        let mkarb = markets_tools("mkarb");
        let mkac_names: Vec<_> = mkac.iter().map(|t| t.name().to_string()).collect();
        let mkarb_names: Vec<_> = mkarb.iter().map(|t| t.name().to_string()).collect();
        for n in &mkac_names {
            assert!(!mkarb_names.contains(n), "{n} collides across namespaces");
        }
    }

    #[test]
    fn read_actions_are_idempotent_write_actions_are_not() {
        let tools = markets_tools("ns");
        let lookup = |name: &str| -> Idempotency {
            tools.iter().find(|t| t.name() == name).unwrap().idempotency()
        };
        assert_eq!(lookup("ns_create_market"), Idempotency::NotIdempotent);
        assert_eq!(lookup("ns_resolve_market"), Idempotency::NotIdempotent);
        assert_eq!(lookup("ns_file_dispute"), Idempotency::NotIdempotent);
        assert_eq!(lookup("ns_rule_dispute"), Idempotency::NotIdempotent);
        assert_eq!(lookup("ns_read_market_state"), Idempotency::Idempotent);
        assert_eq!(lookup("ns_read_settlement_history"), Idempotency::Idempotent);
        assert_eq!(lookup("ns_subscribe_release_feed"), Idempotency::Idempotent);
    }

    #[test]
    fn subset_composition_for_arbiter_persona() {
        let arbiter_tools = vec![
            rule_dispute("mkarb"),
            read_market_state("mkarb"),
            read_settlement_history("mkarb"),
        ];
        let registry = ToolRegistry::new().with_tools(arbiter_tools);
        assert_eq!(registry.len(), 3);
        assert!(registry.lookup("mkarb_rule_dispute").is_some());
        assert!(registry.lookup("mkarb_file_dispute").is_none(), "arbiter cannot file disputes");
    }

    #[tokio::test]
    async fn scaffold_handler_echoes_args() {
        let t = create_market("mkac");
        let call = ToolCall {
            call_id: "c-1".into(),
            from: "markets-auto-create".into(),
            as_bee: None,
            tool_name: "mkac_create_market".into(),
            args: json!({"question": "CPI YoY > 3.2"}),
        };
        let r = t.invoke(call).await;
        assert!(r.ok);
        let v = r.value.unwrap();
        assert_eq!(v["tool"], "mkac_create_market");
        assert_eq!(v["args"]["question"], "CPI YoY > 3.2");
    }
}
