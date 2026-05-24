//! Product-specific tools. Each is a `Tool` impl that composes base `arc_*` calls internally;
//! the runtime wires them against a concrete `Sender` + `SimulationGate` via the safety
//! pipeline before any chain interaction.

use async_trait::async_trait;
use reverb_arc_fs::tools::{Idempotency, Tool, ToolCall, ToolResult};
use serde_json::json;

#[cfg(test)]
use crate::hello::MARKETS_TOOLS;

/// `markets_create_market`: posts a new forward-looking macro market.
/// Internally constructs `Operator.createMarket` calldata and routes through `arc_send_tx`.
pub struct CreateMarket;

#[async_trait]
impl Tool for CreateMarket {
    fn name(&self) -> &'static str { "markets_create_market" }
    fn idempotency(&self) -> Idempotency { Idempotency::NotIdempotent }
    async fn invoke(&self, call: ToolCall) -> ToolResult {
        // Wire-shape only: the runtime overrides `invoke` with a concrete implementation
        // that pulls the substrate Operator address, encodes calldata, runs the safety
        // pipeline, and returns the tx hash.
        ToolResult::ok(
            call.call_id,
            json!({
                "tool": "markets_create_market",
                "status": "scaffold",
                "args": call.args,
            }),
        )
    }
}

/// `markets_resolve_market`: settles a market against a release feed.
pub struct ResolveMarket;

#[async_trait]
impl Tool for ResolveMarket {
    fn name(&self) -> &'static str { "markets_resolve_market" }
    fn idempotency(&self) -> Idempotency { Idempotency::NotIdempotent }
    async fn invoke(&self, call: ToolCall) -> ToolResult {
        ToolResult::ok(
            call.call_id,
            json!({"tool": "markets_resolve_market", "status": "scaffold", "args": call.args}),
        )
    }
}

/// `markets_file_dispute`: challenges a resolution via `RefundProtocolFixed`.
pub struct FileDispute;

#[async_trait]
impl Tool for FileDispute {
    fn name(&self) -> &'static str { "markets_file_dispute" }
    fn idempotency(&self) -> Idempotency { Idempotency::NotIdempotent }
    async fn invoke(&self, call: ToolCall) -> ToolResult {
        ToolResult::ok(
            call.call_id,
            json!({"tool": "markets_file_dispute", "status": "scaffold", "args": call.args}),
        )
    }
}

/// `markets_rule_dispute`: arbiter ruling on a contested resolution.
pub struct RuleDispute;

#[async_trait]
impl Tool for RuleDispute {
    fn name(&self) -> &'static str { "markets_rule_dispute" }
    fn idempotency(&self) -> Idempotency { Idempotency::NotIdempotent }
    async fn invoke(&self, call: ToolCall) -> ToolResult {
        ToolResult::ok(
            call.call_id,
            json!({"tool": "markets_rule_dispute", "status": "scaffold", "args": call.args}),
        )
    }
}

/// `markets_read_market_state`: view current state of any market (read-only).
pub struct ReadMarketState;

#[async_trait]
impl Tool for ReadMarketState {
    fn name(&self) -> &'static str { "markets_read_market_state" }
    fn idempotency(&self) -> Idempotency { Idempotency::Idempotent }
    async fn invoke(&self, call: ToolCall) -> ToolResult {
        ToolResult::ok(
            call.call_id,
            json!({"tool": "markets_read_market_state", "status": "scaffold", "args": call.args}),
        )
    }
}

/// `markets_read_settlement_history`: past settlements for analysis (read-only).
pub struct ReadSettlementHistory;

#[async_trait]
impl Tool for ReadSettlementHistory {
    fn name(&self) -> &'static str { "markets_read_settlement_history" }
    fn idempotency(&self) -> Idempotency { Idempotency::Idempotent }
    async fn invoke(&self, call: ToolCall) -> ToolResult {
        ToolResult::ok(
            call.call_id,
            json!({"tool": "markets_read_settlement_history", "status": "scaffold", "args": call.args}),
        )
    }
}

/// `markets_subscribe_release_feed`: external HTTP polling forager hook wired to humd;
/// emits `chi:release-data` tones on the subscribed sigil.
pub struct SubscribeReleaseFeed;

#[async_trait]
impl Tool for SubscribeReleaseFeed {
    fn name(&self) -> &'static str { "markets_subscribe_release_feed" }
    fn idempotency(&self) -> Idempotency { Idempotency::Idempotent }
    async fn invoke(&self, call: ToolCall) -> ToolResult {
        ToolResult::ok(
            call.call_id,
            json!({"tool": "markets_subscribe_release_feed", "status": "scaffold", "args": call.args}),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use reverb_arc_fs::tools::ToolRegistry;

    fn populated_registry() -> ToolRegistry {
        let mut r = ToolRegistry::new();
        r.register(Box::new(CreateMarket));
        r.register(Box::new(ResolveMarket));
        r.register(Box::new(FileDispute));
        r.register(Box::new(RuleDispute));
        r.register(Box::new(ReadMarketState));
        r.register(Box::new(ReadSettlementHistory));
        r.register(Box::new(SubscribeReleaseFeed));
        r
    }

    #[test]
    fn all_seven_tools_register_into_runtime_registry() {
        let r = populated_registry();
        assert_eq!(r.len(), 7);
        for name in MARKETS_TOOLS {
            assert!(r.lookup(name).is_some(), "missing tool: {name}");
        }
    }

    #[test]
    fn read_tools_are_idempotent_write_tools_are_not() {
        assert_eq!(CreateMarket.idempotency(), Idempotency::NotIdempotent);
        assert_eq!(ResolveMarket.idempotency(), Idempotency::NotIdempotent);
        assert_eq!(FileDispute.idempotency(), Idempotency::NotIdempotent);
        assert_eq!(RuleDispute.idempotency(), Idempotency::NotIdempotent);
        assert_eq!(ReadMarketState.idempotency(), Idempotency::Idempotent);
        assert_eq!(ReadSettlementHistory.idempotency(), Idempotency::Idempotent);
        assert_eq!(SubscribeReleaseFeed.idempotency(), Idempotency::Idempotent);
    }

    #[tokio::test]
    async fn scaffold_invoke_echoes_args_in_value() {
        let t = CreateMarket;
        let call = ToolCall {
            call_id: "c-1".into(),
            from: "markets-auto-create-macro".into(),
            as_bee: Some("markets-auto-create-macro".into()),
            tool_name: "markets_create_market".into(),
            args: serde_json::json!({"question": "CPI YoY > 3.2"}),
        };
        let r = t.invoke(call).await;
        assert!(r.ok);
        let v = r.value.unwrap();
        assert_eq!(v["tool"], "markets_create_market");
        assert_eq!(v["args"]["question"], "CPI YoY > 3.2");
    }
}
