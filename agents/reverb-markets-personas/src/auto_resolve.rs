//! `markets-auto-resolve-{variant}`: settles markets whose resolution criteria are now
//! answerable.

use async_trait::async_trait;
use persona_base::{Decision, Event, EventFilter, PersonaBee};

pub const SYSTEM_PROMPT: &str = "\
Your role is to settle markets whose resolution criteria are now answerable. When a release \
feed publishes the answer for a market you're tracking, propose the resolution via \
markets_resolve_market. The dispute primitive will hold the settlement for the challenge \
window. If the resolution is ambiguous, do not propose; let the market expire unsettled \
(humans can resolve manually).\
";

pub struct AutoResolvePersona {
    pub bee_name: String,
}

impl AutoResolvePersona {
    pub fn new(variant: impl Into<String>) -> Self {
        Self {
            bee_name: format!("markets-auto-resolve-{}", variant.into()),
        }
    }
}

#[async_trait]
impl PersonaBee for AutoResolvePersona {
    fn bee_name(&self) -> &str {
        &self.bee_name
    }

    fn subscribe_topics(&self) -> Vec<String> {
        vec!["reverb-markets/releases/macro".into()]
    }

    fn subscribe_chain_events(&self) -> Vec<EventFilter> {
        vec![EventFilter {
            contract: "0x344b472b7b1ad0a35e11718bc063fd46f4282db2".into(),
            event_signature: "MarketCreated(uint256,address,uint256,bytes32)".into(),
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
        let p = AutoResolvePersona::new("strict");
        assert_eq!(p.bee_name(), "markets-auto-resolve-strict");
    }

    #[tokio::test]
    async fn on_event_returns_prompt_referencing_resolution_role() {
        let p = AutoResolvePersona::new("strict");
        let d = p
            .on_event(Event::Gossip {
                topic: "reverb-markets/releases/macro".into(),
                body: serde_json::json!({"release": "NFP", "value": 184_000}),
            })
            .await;
        match d {
            Decision::Prompt { system_prompt, .. } => {
                assert!(system_prompt.contains("settle markets"));
            }
            Decision::Skip { .. } => panic!("expected prompt"),
        }
    }
}
