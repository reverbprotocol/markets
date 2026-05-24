//! `markets-arbiter-{variant}`: rules on disputes that the auto-dispute persona files.

use async_trait::async_trait;
use persona_base::{Decision, Event, EventFilter, PersonaBee};

pub const SYSTEM_PROMPT: &str = "\
Your role is to rule on disputes filed against proposed market resolutions. Read the dispute \
payload, the original resolution, and the underlying release data. Decide upheld or rejected. \
Emit a tool call to markets_rule_dispute with your ruling and the rationale (the rationale \
becomes the on-chain trace via the IAttributable convention). Be precise: if the release data \
clearly supports the original resolution, reject the dispute. If the release data clearly \
contradicts the original resolution, uphold the dispute. If the call is ambiguous, lean \
toward upholding (the dispute primitive's challenge window is the human-recoverable layer).\
";

pub struct ArbiterPersona {
    pub bee_name: String,
}

impl ArbiterPersona {
    pub fn new(variant: impl Into<String>) -> Self {
        Self {
            bee_name: format!("markets-arbiter-{}", variant.into()),
        }
    }
}

#[async_trait]
impl PersonaBee for ArbiterPersona {
    fn bee_name(&self) -> &str {
        &self.bee_name
    }

    fn subscribe_topics(&self) -> Vec<String> {
        vec!["reverb-markets/disputes/observability".into()]
    }

    fn subscribe_chain_events(&self) -> Vec<EventFilter> {
        // The arbiter listens for disputes filed against the deployed dispute primitive
        // (RefundProtocolFixed proxy on Arc testnet) to detect new contested cases.
        vec![EventFilter {
            contract: "0xc8bF99c55703bc682a3Efd5c8A728EaEda3E121F".into(),
            event_signature: "PaymentCreated(uint256,address,address,uint256,uint256)".into(),
            from_block: None,
        }]
    }

    fn persona_system_prompt(&self) -> Option<String> {
        Some(SYSTEM_PROMPT.into())
    }

    async fn on_event(&self, event: Event) -> Decision {
        let user_prompt = serde_json::to_string_pretty(&event).unwrap_or_default();
        Decision::Prompt {
            sid: format!("{}/{}", self.bee_name, sid_suffix()),
            system_prompt: SYSTEM_PROMPT.into(),
            user_prompt,
        }
    }
}

fn sid_suffix() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{nanos:x}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bee_name_includes_variant() {
        let p = ArbiterPersona::new("conservative");
        assert_eq!(p.bee_name(), "markets-arbiter-conservative");
    }

    #[test]
    fn subscribes_to_dispute_primitive_chain_events() {
        let p = ArbiterPersona::new("conservative");
        let evts = p.subscribe_chain_events();
        assert_eq!(evts.len(), 1);
        // The substrate's RefundProtocolFixed proxy address on Arc testnet
        assert_eq!(evts[0].contract, "0xc8bF99c55703bc682a3Efd5c8A728EaEda3E121F");
    }

    #[tokio::test]
    async fn on_event_returns_prompt_referencing_ruling_role() {
        let p = ArbiterPersona::new("conservative");
        let d = p
            .on_event(Event::Gossip {
                topic: "reverb-markets/disputes/observability".into(),
                body: serde_json::json!({"dispute_id": 9}),
            })
            .await;
        match d {
            Decision::Prompt { system_prompt, .. } => {
                assert!(system_prompt.contains("rule on disputes"));
            }
            Decision::Skip { .. } => panic!("expected prompt"),
        }
    }
}
