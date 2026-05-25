//! `markets-auto-create` persona binary. One process, one EOA, one stable ed25519 hid,
//! one scoped tool surface (create_market + reads + release feed). The forager IS this bee.
//!
//! Bee name: `markets-auto-create-<variant>` (variant from arg 1, default `default`).
//! Tool namespace: `mkac_*`.
//! Allowed contracts: Reverb Markets Operator on Arc testnet.
//!
//! Env:
//! - `HUM_BEE_KEY_PATH` - path to the EOA hex keyfile. Default
//!   `~/.config/hum/<bee_name>/key.hex` (must be 0600).
//! - `XDG_STATE_HOME` - hum bee identity root (defaults via `dirs::state_dir`).
//!
//! The runtime that supervises this binary is expected to call `humd` attach after the
//! forager is built. This main constructs the forager + persona spec, logs the resulting
//! hid + tool surface, and exits successfully.

use std::path::PathBuf;
use std::process::ExitCode;

use persona_base::PersonaBee;
use reverb_arc_fs::{BeeIdentity, PersonaForager, PrivateKey};
use reverb_markets_arc_fs::tools::{
    create_market, read_market_state, read_settlement_history, subscribe_release_feed,
};
use reverb_markets_personas::AutoCreatePersona;

const NAMESPACE: &str = "mkac";
const OPERATOR: &str = "0x344b472b7b1ad0a35e11718bc063fd46f4282db2";

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("markets-auto-create: fatal: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let variant = std::env::args().nth(1).unwrap_or_else(|| "default".into());
    let persona = AutoCreatePersona::new(&variant);
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
            create_market(NAMESPACE),
            read_market_state(NAMESPACE),
            read_settlement_history(NAMESPACE),
            subscribe_release_feed(NAMESPACE),
        ])
        .allowed_contracts([OPERATOR.to_string()])
        .wire("reverb-markets/arc-fs")
        .source(
            "https://github.com/reverbprotocol/markets/tree/main/agents/reverb-markets-personas",
        )
        .build()?;

    print_attach_summary(&bee_name, &forager, &persona);
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

fn print_attach_summary(bee_name: &str, forager: &PersonaForager, persona: &AutoCreatePersona) {
    println!("bee_name: {bee_name}");
    println!("hid: {}", forager.hello.hid);
    println!("wire: {}", forager.hello.propensity.wire);
    println!("tools: {}", forager.hello.tools.join(", "));
    println!("allowed_contracts: {}", forager.allowed_contracts.join(", "));
    println!("topics: {}", persona.subscribe_topics().join(", "));
    println!("chain_events: {}", persona.subscribe_chain_events().len());
}
