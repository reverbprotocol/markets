//! `markets-auto-create-{variant}`: identifies newly-released macro data and decides whether
//! to create a forward-looking market on the next release.

use async_trait::async_trait;
use persona_base::{Decision, Event, EventFilter, PersonaBee};

pub const SYSTEM_PROMPT: &str = "\
Your role is to identify newly-released macro data and decide whether to create a new \
forward-looking market on the next release. Your universe is monthly CPI, FOMC, NFP, PPI, \
retail sales. When a release lands, decide: is the next-print question well-formed? Is there \
commercial value (likely volume)? If yes, emit a tool call to markets_create_market with a \
binary question, resolution date, and YES/NO thresholds. If no, log and skip.\
";

pub struct AutoCreatePersona {
    pub bee_name: String,
}

impl AutoCreatePersona {
    pub fn new(variant: impl Into<String>) -> Self {
        Self {
            bee_name: format!("markets-auto-create-{}", variant.into()),
        }
    }
}

#[async_trait]
impl PersonaBee for AutoCreatePersona {
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
            sid: format!("{}/{}", self.bee_name, uuid_like()),
            system_prompt: SYSTEM_PROMPT.into(),
            user_prompt,
        }
    }
}

/// Cheap unique-id (not a real uuid; deterministic-enough for sid namespacing). The runtime
/// may replace this with a proper monotonic-id source.
fn uuid_like() -> String {
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
        let p = AutoCreatePersona::new("macro");
        assert_eq!(p.bee_name(), "markets-auto-create-macro");
    }

    #[test]
    fn subscribes_to_release_topic_and_chain_event() {
        let p = AutoCreatePersona::new("macro");
        assert!(p.subscribe_topics().contains(&"reverb-markets/releases/macro".to_string()));
        let evts = p.subscribe_chain_events();
        assert_eq!(evts.len(), 1);
        assert_eq!(evts[0].contract, "0x344b472b7b1ad0a35e11718bc063fd46f4282db2");
    }

    #[tokio::test]
    async fn on_event_returns_prompt_with_persona_system_prompt() {
        let p = AutoCreatePersona::new("macro");
        let d = p
            .on_event(Event::Gossip {
                topic: "reverb-markets/releases/macro".into(),
                body: serde_json::json!({"release": "CPI", "value": 3.18}),
            })
            .await;
        match d {
            Decision::Prompt { system_prompt, sid, user_prompt } => {
                assert!(system_prompt.contains("forward-looking market"));
                assert!(sid.starts_with("markets-auto-create-macro/"));
                assert!(user_prompt.contains("CPI"));
            }
            Decision::Skip { .. } => panic!("expected prompt"),
        }
    }
}
