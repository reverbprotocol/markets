use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::time::Duration;
use tokio::time::sleep;
use tracing::{error, info, warn};

mod feeds;
mod operator;
mod parser;
mod post;
mod registry;
mod trace;

#[derive(Parser, Debug)]
#[command(version, about = "Resolver daemon for the project-reverb operator")]
struct Cli {
    /// Path to the markets registry. Defaults to ./registry/markets.json
    #[arg(long, env = "REGISTRY_PATH", default_value = "registry/markets.json")]
    registry: PathBuf,

    /// JSON-RPC URL for the chain hosting the operator.
    #[arg(long, env = "RPC_URL")]
    rpc_url: String,

    /// Operator contract address (0x-prefixed hex).
    #[arg(long, env = "OPERATOR_ADDRESS")]
    operator_address: String,

    /// Resolver private key (0x-prefixed hex). Read from env, never logged.
    #[arg(long, env = "RESOLVER_PRIVATE_KEY", hide_env_values = true)]
    resolver_private_key: String,

    /// Optional FRED API key. Without it, FRED-backed markets are skipped.
    #[arg(long, env = "FRED_API_KEY", hide_env_values = true)]
    fred_api_key: Option<String>,

    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Resolve markets once and exit.
    Once {
        /// Optional: restrict to a single market ID.
        #[arg(long)]
        market_id: Option<u64>,
    },
    /// Watch the registry and resolve markets as they become eligible.
    Watch {
        /// Polling interval in seconds.
        #[arg(long, default_value_t = 60)]
        interval_secs: u64,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("auto_resolve=info,warn")),
        )
        .init();

    let cli = Cli::parse();
    let reg = registry::load(&cli.registry)
        .with_context(|| format!("loading registry from {}", cli.registry.display()))?;
    info!(markets = reg.markets.len(), "registry loaded");

    let op = operator::OperatorClient::new(
        &cli.rpc_url,
        &cli.operator_address,
        &cli.resolver_private_key,
    )
    .await
    .context("connecting to operator")?;
    info!(operator = %cli.operator_address, signer = %op.signer_address(), "operator client ready");

    let http = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .user_agent("project-reverb/auto-resolve/0.1")
        .build()?;

    let fred_key = cli.fred_api_key.as_deref();

    match cli.cmd {
        Cmd::Once { market_id } => {
            run_once(&reg, market_id, &http, fred_key, &op).await?;
        }
        Cmd::Watch { interval_secs } => loop {
            if let Err(e) = run_once(&reg, None, &http, fred_key, &op).await {
                error!(err = %e, "watch iteration failed");
            }
            sleep(Duration::from_secs(interval_secs)).await;
        },
    }

    Ok(())
}

async fn run_once(
    reg: &registry::Registry,
    only_market_id: Option<u64>,
    http: &reqwest::Client,
    fred_key: Option<&str>,
    op: &operator::OperatorClient,
) -> Result<()> {
    for m in &reg.markets {
        if let Some(only) = only_market_id {
            if m.market_id != only {
                continue;
            }
        }

        let span = tracing::info_span!("market", id = m.market_id, feed = %m.feed);
        let _g = span.enter();

        match resolve_one(m, http, fred_key, op).await {
            Ok(Some(outcome)) => info!(outcome, "submitted resolution"),
            Ok(None) => info!("not eligible yet, skipped"),
            Err(e) => error!(err = ?e, "resolution failed"),
        }
    }
    Ok(())
}

async fn resolve_one(
    m: &registry::MarketSpec,
    http: &reqwest::Client,
    fred_key: Option<&str>,
    op: &operator::OperatorClient,
) -> Result<Option<u8>> {
    let observation = match m.feed.as_str() {
        "bls" => feeds::bls::fetch_yoy_percent_change(http, &m.series_id, m.release_year)
            .await
            .context("BLS fetch")?,
        "fred" => {
            let key = fred_key.ok_or_else(|| {
                anyhow!("market is FRED-backed but FRED_API_KEY unset; skipping")
            })?;
            feeds::fred::fetch_yoy_percent_change(http, key, &m.series_id, m.release_year)
                .await
                .context("FRED fetch")?
        }
        other => return Err(anyhow!("unknown feed kind: {}", other)),
    };

    let outcome = parser::derive_outcome(observation, m);
    info!(value = observation, threshold = m.threshold, comparison = %m.comparison, outcome, "derived outcome");

    // Reasoning-trace pinning per IMPROVISE.md Move 10. v0 writes locally;
    // ~/.reverb/traces/<sha>.json. Real IPFS pinning lands when token provisioned.
    let mut t = trace::from_decision(m, observation, outcome);
    let (sha_pre, _path_pre) = trace::pin_local(&t)?;
    info!(trace_sha = %sha_pre, "pre-tx trace pinned locally");

    match op.propose_resolution(m.market_id, outcome).await {
        Ok(tx_hash) => {
            info!(tx = %tx_hash, "proposeResolution submitted");
            t.tx_hash = Some(tx_hash.clone());
            let (sha_post, path_post) = trace::pin_local(&t)?;
            info!(trace_sha = %sha_post, path = %path_post.display(), "post-tx trace pinned locally");

            // Cross-post receipts per IMPROVISE.md Move 12. v0 stubs to ~/.reverb/posts/.
            let receipt = post::build_receipt(
                m.market_id,
                format!("{} {} {}", m.feed, m.series_id, m.comparison),
                observation,
                m.threshold,
                outcome,
                tx_hash.clone(),
                "https://explorer.testnet.arc.network",
                sha_post,
            );
            match post::dispatch_all(&receipt) {
                Ok(results) => {
                    for r in &results {
                        info!(channel = r.channel, status = r.status, artifact = %r.artifact.display(), "post stub written");
                    }
                }
                Err(e) => warn!(err = ?e, "post fan-out failed"),
            }

            Ok(Some(outcome))
        }
        Err(e) => {
            // The operator reverts before resolutionDeadline. That's expected; surface as skip.
            let s = format!("{e:#}");
            if s.contains("ResolutionDeadlineNotReached") {
                warn!("resolution deadline not reached on-chain; will retry");
                Ok(None)
            } else {
                Err(e)
            }
        }
    }
}
