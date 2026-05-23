use anyhow::{anyhow, Context, Result};
use serde::Deserialize;

const FRED_URL: &str = "https://api.stlouisfed.org/fred/series/observations";

#[derive(Debug, Deserialize)]
struct FredResponse {
    observations: Vec<FredObservation>,
}

#[derive(Debug, Deserialize)]
struct FredObservation {
    date: String,
    value: String,
}

/// Fetch FRED observations for `series_id` and compute YoY % change for the
/// latest observation falling within `release_year`.
pub async fn fetch_yoy_percent_change(
    http: &reqwest::Client,
    api_key: &str,
    series_id: &str,
    release_year: u32,
) -> Result<f64> {
    let prior = release_year - 1;
    let resp = http
        .get(FRED_URL)
        .query(&[
            ("series_id", series_id),
            ("api_key", api_key),
            ("file_type", "json"),
            ("observation_start", &format!("{}-01-01", prior)),
            ("observation_end", &format!("{}-12-31", release_year)),
        ])
        .send()
        .await
        .context("FRED GET")?;
    let status = resp.status();
    let text = resp.text().await?;
    if !status.is_success() {
        return Err(anyhow!("FRED HTTP {}: {}", status, text));
    }

    let parsed: FredResponse = serde_json::from_str(&text)
        .with_context(|| format!("decoding FRED response: {}", &text[..text.len().min(400)]))?;

    let release_prefix = format!("{}-", release_year);
    let prior_prefix = format!("{}-", prior);

    let latest = parsed
        .observations
        .iter()
        .filter(|o| o.date.starts_with(&release_prefix) && o.value != ".")
        .last()
        .ok_or_else(|| anyhow!("no FRED observation in release_year {}", release_year))?;

    // Match same month in prior year.
    let month = &latest.date[5..7];
    let prior_match_prefix = format!("{}{}", prior_prefix, month);
    let prior_match = parsed
        .observations
        .iter()
        .find(|o| o.date.starts_with(&prior_match_prefix) && o.value != ".")
        .ok_or_else(|| anyhow!("no prior-year FRED match for month {}", month))?;

    let cur: f64 = latest.value.parse()?;
    let prev: f64 = prior_match.value.parse()?;
    if prev == 0.0 {
        return Err(anyhow!("prior-year FRED value is zero"));
    }
    Ok(((cur - prev) / prev) * 100.0)
}
