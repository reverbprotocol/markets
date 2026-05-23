use crate::registry::MarketSpec;

/// Apply the registry's comparison and pick the outcome.
pub fn derive_outcome(observation: f64, m: &MarketSpec) -> u8 {
    let truthy = match m.comparison.as_str() {
        "gt" => observation > m.threshold,
        "gte" => observation >= m.threshold,
        "lt" => observation < m.threshold,
        "lte" => observation <= m.threshold,
        "eq" => (observation - m.threshold).abs() < f64::EPSILON,
        _ => panic!("unknown comparison: {}", m.comparison),
    };
    if truthy { m.outcome_if_true } else { m.outcome_if_false }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::MarketSpec;

    fn spec(comparison: &str, threshold: f64, t: u8, f: u8) -> MarketSpec {
        MarketSpec {
            market_id: 0,
            comment: String::new(),
            feed: "bls".into(),
            series_id: "CUUR0000SA0".into(),
            release_year: 2026,
            release_month: 5,
            computation: "yoy_percent_change".into(),
            threshold,
            comparison: comparison.into(),
            outcome_if_true: t,
            outcome_if_false: f,
        }
    }

    #[test]
    fn gt_above_threshold_picks_true_outcome() {
        let s = spec("gt", 3.2, 0, 1);
        assert_eq!(derive_outcome(3.5, &s), 0);
    }

    #[test]
    fn gt_below_threshold_picks_false_outcome() {
        let s = spec("gt", 3.2, 0, 1);
        assert_eq!(derive_outcome(3.1, &s), 1);
    }

    #[test]
    fn gt_at_threshold_picks_false_outcome() {
        let s = spec("gt", 3.2, 0, 1);
        assert_eq!(derive_outcome(3.2, &s), 1);
    }

    #[test]
    fn gte_at_threshold_picks_true_outcome() {
        let s = spec("gte", 3.2, 0, 1);
        assert_eq!(derive_outcome(3.2, &s), 0);
    }

    #[test]
    fn lt_below_picks_true() {
        let s = spec("lt", 3.2, 0, 1);
        assert_eq!(derive_outcome(2.9, &s), 0);
    }

    /// Historical-replay reference per IMPROVISE.md Move 13.
    /// Given a known historical CPI YoY value, the parser must derive the same
    /// outcome a fresh agent cloning this repo would derive. Determinism is the
    /// load-bearing property of the reference implementation; the test fixture
    /// here is the canonical "did the agent's logic survive a fork" check.
    #[test]
    fn replay_historical_cpi_april_2026_above_threshold() {
        let s = spec("gt", 3.2, 0, 1);
        // Observed YoY% for series CUUR0000SA0 against an April 2026 release window
        // matches the live-network resolution captured at apps/dispute-escrow on
        // 2026-05-10 (smoke-test artifact: tx 0xb326de09…). Value is fixed in the
        // test so the replay is reproducible without an HTTP call.
        let observation = 3.256_420_439_088_316_7_f64;
        let outcome = derive_outcome(observation, &s);
        assert_eq!(outcome, 0, "replay outcome must match reference");
    }
}
