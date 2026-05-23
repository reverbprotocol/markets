use anyhow::{Context, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::PathBuf;

use crate::registry::MarketSpec;

/// Reasoning trace for a resolver decision per IMPROVISE.md Move 10.
///
/// v0 stubs the IPFS-pinning path by writing the trace to `~/.reverb/traces/<sha>.json`
/// and treating the trace's SHA-256 as a stand-in for the IPFS CID. Real Pinata pinning
/// lands when the API token is provisioned (tracked in /debt/ledger.json).
#[derive(Debug, Serialize, Deserialize)]
pub struct ResolverTrace {
    pub schema_version: u8,
    pub timestamp_utc: String,
    pub market_id: u64,
    pub feed: String,
    pub series_id: String,
    pub release_year: u32,
    pub release_month: u32,
    pub computation: String,
    pub observed_value: f64,
    pub threshold: f64,
    pub comparison: String,
    pub derived_outcome: u8,
    pub action: String,
    pub tx_hash: Option<String>,
    pub data_source_url: String,
    pub agent_version: String,
}

impl ResolverTrace {
    pub fn sha256_hex(&self) -> Result<String> {
        let raw = serde_json::to_vec(self).context("serializing trace")?;
        let mut h = Sha256::new();
        h.update(&raw);
        Ok(format!("{:x}", h.finalize()))
    }
}

pub fn from_decision(spec: &MarketSpec, observed_value: f64, derived_outcome: u8) -> ResolverTrace {
    ResolverTrace {
        schema_version: 1,
        timestamp_utc: Utc::now().to_rfc3339(),
        market_id: spec.market_id,
        feed: spec.feed.clone(),
        series_id: spec.series_id.clone(),
        release_year: spec.release_year,
        release_month: spec.release_month,
        computation: spec.computation.clone(),
        observed_value,
        threshold: spec.threshold,
        comparison: spec.comparison.clone(),
        derived_outcome,
        action: "proposeResolution".to_string(),
        tx_hash: None,
        data_source_url: data_source_url_for(&spec.feed, &spec.series_id),
        agent_version: env!("CARGO_PKG_VERSION").to_string(),
    }
}

fn data_source_url_for(feed: &str, series_id: &str) -> String {
    match feed {
        "bls" => format!("https://api.bls.gov/publicAPI/v2/timeseries/data/{}", series_id),
        "fred" => format!(
            "https://api.stlouisfed.org/fred/series/observations?series_id={}",
            series_id
        ),
        "census" => "https://api.census.gov".to_string(),
        _ => format!("unknown-feed:{}", feed),
    }
}

/// Persist the trace under `~/.reverb/traces/<sha256>.json`. Returns the SHA-256 hex.
pub fn pin_local(trace: &ResolverTrace) -> Result<(String, PathBuf)> {
    let sha = trace.sha256_hex()?;
    let dir = traces_dir()?;
    fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
    let path = dir.join(format!("{}.json", &sha));
    let json = serde_json::to_string_pretty(trace)?;
    fs::write(&path, json).with_context(|| format!("writing trace to {}", path.display()))?;
    Ok((sha, path))
}

fn traces_dir() -> Result<PathBuf> {
    let home = std::env::var("HOME").context("HOME unset")?;
    Ok(PathBuf::from(home).join(".reverb").join("traces"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::MarketSpec;

    fn sample_spec() -> MarketSpec {
        MarketSpec {
            market_id: 0,
            comment: String::new(),
            feed: "bls".into(),
            series_id: "CUUR0000SA0".into(),
            release_year: 2026,
            release_month: 5,
            computation: "yoy_percent_change".into(),
            threshold: 3.2,
            comparison: "gt".into(),
            outcome_if_true: 0,
            outcome_if_false: 1,
        }
    }

    #[test]
    fn sha_is_stable_for_same_inputs() {
        let s = sample_spec();
        let t1 = from_decision(&s, 3.256, 0);
        let t2 = ResolverTrace { timestamp_utc: t1.timestamp_utc.clone(), ..from_decision(&s, 3.256, 0) };
        assert_eq!(t1.sha256_hex().unwrap(), t2.sha256_hex().unwrap());
    }

    #[test]
    fn sha_changes_when_outcome_differs() {
        let s = sample_spec();
        let t1 = from_decision(&s, 3.256, 0);
        let t2 = ResolverTrace { derived_outcome: 1, ..from_decision(&s, 3.256, 0) };
        let t2 = ResolverTrace { timestamp_utc: t1.timestamp_utc.clone(), ..t2 };
        assert_ne!(t1.sha256_hex().unwrap(), t2.sha256_hex().unwrap());
    }

    #[test]
    fn data_source_url_recognizes_known_feeds() {
        assert!(data_source_url_for("bls", "CUUR0000SA0").contains("bls.gov"));
        assert!(data_source_url_for("fred", "CPIAUCSL").contains("stlouisfed.org"));
    }
}
