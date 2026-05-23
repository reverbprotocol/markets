//! Cross-post pipeline per IMPROVISE.md Move 12.
//!
//! Renders a receipt for a settled market and fans it out across four channels:
//! X, Farcaster, Bluesky, nostr. v0 stubs each adapter to write the formatted
//! post body to `~/.reverb/posts/<event_id>/<channel>.{txt,json}`. A real adapter
//! lands when the channel-specific credential is provisioned (tracked in
//! `/debt/ledger.json`).
//!
//! Channel-specific behaviors at v0:
//! - X: paid API tier required; always stubs to file.
//! - Farcaster: Neynar free tier covers it; stubs until NEYNAR_API_KEY env is set.
//! - Bluesky: atproto free tier; stubs until BLUESKY_HANDLE+BLUESKY_APP_PASSWORD env is set.
//! - nostr: free public relays; stubs until NOSTR_PRIVATE_KEY env is set.
//!
//! The formatter is identical across channels; only the dispatch layer differs.

use anyhow::{Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Receipt {
    pub event_id: String,
    pub market_id: u64,
    pub question_summary: String,
    pub observed_value: f64,
    pub threshold: f64,
    pub outcome: u8,
    pub outcome_label: String,
    pub tx_hash: String,
    pub explorer_url: String,
    pub trace_sha: String,
}

pub fn body(r: &Receipt) -> String {
    format!(
        "{question}\n\n\
         observed: {value}  threshold: {threshold}  outcome: {label} ({outcome})\n\
         tx: {tx}\n\
         trace: {trace}\n\
         explorer: {explorer}\n\
         #adiled #arc #reverb",
        question = r.question_summary,
        value = r.observed_value,
        threshold = r.threshold,
        label = r.outcome_label,
        outcome = r.outcome,
        tx = r.tx_hash,
        trace = &r.trace_sha[..16],
        explorer = r.explorer_url,
    )
}

pub struct DispatchResult {
    pub channel: &'static str,
    pub status: &'static str,
    pub artifact: PathBuf,
}

pub fn dispatch_all(r: &Receipt) -> Result<Vec<DispatchResult>> {
    let dir = posts_dir(&r.event_id)?;
    fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
    let body_text = body(r);

    let mut out = Vec::new();
    for (channel, cred_env) in [
        ("x", "X_BEARER_TOKEN"),
        ("farcaster", "NEYNAR_API_KEY"),
        ("bluesky", "BLUESKY_APP_PASSWORD"),
        ("nostr", "NOSTR_PRIVATE_KEY"),
    ] {
        let path = dir.join(format!("{}.txt", channel));
        fs::write(&path, &body_text)
            .with_context(|| format!("writing {} stub to {}", channel, path.display()))?;
        let status = if std::env::var(cred_env).is_ok() {
            // Real adapter would dispatch here. v0: still stubs to file with credential present.
            "credential-present-stub"
        } else {
            "credential-missing-stub"
        };
        out.push(DispatchResult { channel, status, artifact: path });
    }
    Ok(out)
}

fn posts_dir(event_id: &str) -> Result<PathBuf> {
    let home = std::env::var("HOME").context("HOME unset")?;
    Ok(PathBuf::from(home).join(".reverb").join("posts").join(event_id))
}

pub fn build_receipt(
    market_id: u64,
    question_summary: impl Into<String>,
    observed_value: f64,
    threshold: f64,
    outcome: u8,
    tx_hash: impl Into<String>,
    explorer_base: &str,
    trace_sha: impl Into<String>,
) -> Receipt {
    let tx_hash = tx_hash.into();
    let explorer_url = format!("{}/tx/{}", explorer_base.trim_end_matches('/'), tx_hash.trim_start_matches("0x"));
    let outcome_label = match outcome {
        0 => "YES".to_string(),
        1 => "NO".to_string(),
        n => format!("OUT_{}", n),
    };
    Receipt {
        event_id: format!("{}-{}", Utc::now().format("%Y%m%dT%H%M%SZ"), market_id),
        market_id,
        question_summary: question_summary.into(),
        observed_value,
        threshold,
        outcome,
        outcome_label,
        tx_hash,
        explorer_url,
        trace_sha: trace_sha.into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Receipt {
        build_receipt(
            0,
            "CPI YoY > 3.2% in April 2026",
            3.2564,
            3.2,
            0,
            "0xb326de09b7a9e4f3709f27bac03f61d3946d46dac6dcd914b4f644d0ec336970",
            "https://explorer.testnet.arc.network",
            "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        )
    }

    #[test]
    fn body_includes_outcome_and_tx() {
        let b = body(&fixture());
        assert!(b.contains("YES"));
        assert!(b.contains("0xb326de09"));
        assert!(b.contains("explorer.testnet.arc.network"));
    }

    #[test]
    fn outcome_label_maps_correctly() {
        let r = build_receipt(0, "q", 0.0, 0.0, 1, "0xdead", "https://e", "0".repeat(64));
        assert_eq!(r.outcome_label, "NO");
    }
}
