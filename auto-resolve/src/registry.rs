use serde::Deserialize;
use std::fs;
use std::path::Path;

#[derive(Debug, Deserialize)]
pub struct Registry {
    pub markets: Vec<MarketSpec>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct MarketSpec {
    pub market_id: u64,
    #[serde(default)]
    #[allow(dead_code)]
    pub comment: String,
    /// "bls" | "fred" | "census"
    pub feed: String,
    /// Series identifier. For BLS: e.g. "CUUR0000SA0". For FRED: e.g. "CPIAUCSL".
    pub series_id: String,
    /// Year and month of the release the resolver should look for.
    pub release_year: u32,
    /// Currently informational; v0 picks the latest monthly observation in release_year.
    /// v1 will filter exactly to (release_year, release_month).
    #[allow(dead_code)]
    pub release_month: u32,
    /// "yoy_percent_change" | "value" | "mom_percent_change". v0 only supports yoy_percent_change.
    #[allow(dead_code)]
    pub computation: String,
    /// Numeric threshold for the question.
    pub threshold: f64,
    /// "gt" | "gte" | "lt" | "lte" | "eq"
    pub comparison: String,
    /// Outcome to propose if comparison(observation, threshold) is true.
    pub outcome_if_true: u8,
    /// Outcome to propose if comparison(observation, threshold) is false.
    pub outcome_if_false: u8,
}

pub fn load(path: &Path) -> anyhow::Result<Registry> {
    let raw = fs::read_to_string(path)?;
    let r: Registry = serde_json::from_str(&raw)?;
    Ok(r)
}
