use anyhow::{anyhow, Context, Result};
use serde::Deserialize;

const BLS_URL: &str = "https://api.bls.gov/publicAPI/v2/timeseries/data/";

#[derive(Debug, Deserialize)]
struct BlsResponse {
    status: String,
    #[serde(rename = "Results")]
    results: BlsResults,
}

#[derive(Debug, Deserialize)]
struct BlsResults {
    series: Vec<BlsSeries>,
}

#[derive(Debug, Deserialize)]
struct BlsSeries {
    #[serde(rename = "seriesID")]
    #[allow(dead_code)]
    series_id: String,
    data: Vec<BlsDatum>,
}

#[derive(Debug, Deserialize)]
struct BlsDatum {
    year: String,
    /// "M01".."M12" for monthly series; "M13" for annual average.
    period: String,
    value: String,
}

/// Fetch the latest year's worth of observations for a BLS monthly series and return
/// the year-over-year percent change for the most recent month within `release_year`.
///
/// Example: for CPI series CUUR0000SA0 with release_year 2026, returns the YoY %
/// for the latest month present in 2026 vs the same month in 2025.
pub async fn fetch_yoy_percent_change(
    http: &reqwest::Client,
    series_id: &str,
    release_year: u32,
) -> Result<f64> {
    let url = format!("{}{}", BLS_URL, series_id);
    let prior = release_year - 1;
    let body = serde_json::json!({
        "seriesid": [series_id],
        "startyear": prior.to_string(),
        "endyear": release_year.to_string(),
    });

    let resp = http
        .post(&url)
        .json(&body)
        .send()
        .await
        .context("BLS POST")?;
    let status = resp.status();
    let text = resp.text().await?;
    if !status.is_success() {
        return Err(anyhow!("BLS HTTP {}: {}", status, text));
    }

    let parsed: BlsResponse = serde_json::from_str(&text)
        .with_context(|| format!("decoding BLS response: {}", &text[..text.len().min(400)]))?;
    if parsed.status != "REQUEST_SUCCEEDED" {
        return Err(anyhow!("BLS status {}", parsed.status));
    }

    let series = parsed
        .results
        .series
        .into_iter()
        .next()
        .ok_or_else(|| anyhow!("BLS returned no series"))?;

    // Find the latest monthly observation in release_year (period M01..M12, not M13).
    let release_year_s = release_year.to_string();
    let prior_year_s = prior.to_string();

    let latest_release = series
        .data
        .iter()
        .filter(|d| d.year == release_year_s && d.period.starts_with('M') && d.period != "M13")
        .max_by_key(|d| d.period.clone())
        .ok_or_else(|| anyhow!("no monthly observation for release_year {}", release_year))?;

    let prior_match = series
        .data
        .iter()
        .find(|d| d.year == prior_year_s && d.period == latest_release.period)
        .ok_or_else(|| {
            anyhow!(
                "no prior-year match for period {} in {}",
                latest_release.period,
                prior_year_s
            )
        })?;

    let cur: f64 = latest_release.value.parse()?;
    let prev: f64 = prior_match.value.parse()?;
    if prev == 0.0 {
        return Err(anyhow!("prior-year value is zero"));
    }
    Ok(((cur - prev) / prev) * 100.0)
}
