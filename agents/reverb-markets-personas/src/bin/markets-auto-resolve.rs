//! `markets-auto-resolve` persona binary. Tool namespace: `mkar_*`. Scoped to
//! resolve_market + reads. Allowed contracts: Reverb Markets Operator.

use std::path::PathBuf;
use std::process::ExitCode;

use persona_base::PersonaBee;
use reverb_arc_fs::{BeeIdentity, PersonaForager, PrivateKey};
use reverb_markets_arc_fs::tools::{
    read_market_state, read_settlement_history, resolve_market,
};
use reverb_markets_personas::AutoResolvePersona;

const NAMESPACE: &str = "mkar";
const OPERATOR: &str = "0x344b472b7b1ad0a35e11718bc063fd46f4282db2";

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("markets-auto-resolve: fatal: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let variant = std::env::args().nth(1).unwrap_or_else(|| "default".into());
    let persona = AutoResolvePersona::new(&variant);
    let bee_name = persona.bee_name().to_string();

    let identity = BeeIdentity::load_or_mint(&bee_name)?;
    let key_path = key_path_for(&bee_name);
    let private_key = PrivateKey::load(&key_path)?;

    let forager = PersonaForager::builder()
        .bee_name(&bee_name)
        .identity(identity)
        .private_key(private_key)
        .namespace(NAMESPACE)
        .with_tools([
            resolve_market(NAMESPACE),
            read_market_state(NAMESPACE),
            read_settlement_history(NAMESPACE),
        ])
        .allowed_contracts([OPERATOR.to_string()])
        .wire("reverb-markets/arc-fs")
        .source(
            "https://github.com/reverbprotocol/markets/tree/main/agents/reverb-markets-personas",
        )
        .build()?;

    println!("bee_name: {bee_name}");
    println!("hid: {}", forager.hello.hid);
    println!("wire: {}", forager.hello.propensity.wire);
    println!("tools: {}", forager.hello.tools.join(", "));
    println!("allowed_contracts: {}", forager.allowed_contracts.join(", "));
    println!("topics: {}", persona.subscribe_topics().join(", "));
    println!("chain_events: {}", persona.subscribe_chain_events().len());
    Ok(())
}

fn key_path_for(bee_name: &str) -> PathBuf {
    if let Ok(custom) = std::env::var("HUM_BEE_KEY_PATH") {
        return PathBuf::from(custom);
    }
    let base = std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            dirs::home_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join(".config")
        });
    base.join("hum").join(bee_name).join("key.hex")
}
