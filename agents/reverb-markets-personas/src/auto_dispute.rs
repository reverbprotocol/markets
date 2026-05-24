//! `markets-auto-dispute-{variant}`: monitors proposed resolutions and disputes any that
//! misread the release data.

use async_trait::async_trait;
use persona_base::{Decision, Event, EventFilter, PersonaBee};

pub const SYSTEM_PROMPT: &str = "\
Your role is to monitor proposed resolutions and dispute any that misread the release data. \
Read the release data the resolver proposed against. If your reading differs (e.g. resolver \
proposed YES on `CPI YoY > 3.2` but the actual print was 3.18), emit a tool call to \
markets_file_dispute. If the resolution looks correct, log and skip.\
";

pub struct AutoDisputePersona {
    pub bee_name: String,
}

impl AutoDisputePersona {
    pub fn new(variant: impl Into<String>) -> Self {
        Self {
            bee_name: format!("markets-auto-dispute-{}", variant.into()),
        }
    }
}

#[async_trait]
impl PersonaBee for AutoDisputePersona {
    fn bee_name(&self) -> &str {
        &self.bee_name
    }

    fn subscribe_topics(&self) -> Vec<String> {
        vec!["reverb-markets/disputes/observability".into()]
    }

    fn subscribe_chain_events(&self) -> Vec<EventFilter> {
        vec![EventFilter {
            contract: "0x344b472b7b1ad0a35e11718bc063fd46f4282db2".into(),
            event_signature: "ResolutionProposed(uint256,address,bytes32,uint256)".into(),
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
        let p = AutoDisputePersona::new("aggressive");
        assert_eq!(p.bee_name(), "markets-auto-dispute-aggressive");
    }

    #[test]
    fn subscribes_to_dispute_observability_topic() {
        let p = AutoDisputePersona::new("aggressive");
        assert!(p
            .subscribe_topics()
            .contains(&"reverb-markets/disputes/observability".to_string()));
    }

    #[tokio::test]
    async fn on_event_returns_prompt_referencing_dispute_role() {
        let p = AutoDisputePersona::new("aggressive");
        let d = p
            .on_event(Event::ChainEvent {
                contract: "0x344b472b7b1ad0a35e11718bc063fd46f4282db2".into(),
                event: "ResolutionProposed".into(),
                data: serde_json::json!({"marketId": 7, "outcome": "YES"}),
            })
            .await;
        match d {
            Decision::Prompt { system_prompt, .. } => {
                assert!(system_prompt.contains("dispute"));
            }
            Decision::Skip { .. } => panic!("expected prompt"),
        }
    }
}
