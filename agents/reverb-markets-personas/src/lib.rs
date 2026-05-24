//! # reverb-markets-personas
//!
//! Four sovereign persona bees for Reverb Markets:
//!
//! - [`auto_create::AutoCreatePersona`] watches macro release feeds; decides whether to
//!   create a new forward-looking market on the next print.
//! - [`auto_resolve::AutoResolvePersona`] settles markets whose resolution criteria are now
//!   answerable.
//! - [`auto_dispute::AutoDisputePersona`] monitors proposed resolutions and disputes any that
//!   misread the release data.
//! - [`arbiter::ArbiterPersona`] rules on disputes the auto-dispute persona files.
//!
//! Each implements `PersonaBee` from `persona-base`. Each is a thin asker; the actual decision
//! happens inside the worker bee's sid (claude-cli, vercel-ai, ollama, etc.). The role-overlay
//! system prompts define the persona's behavior; the runtime injects the worker transport.

pub mod auto_create;
pub mod auto_resolve;
pub mod auto_dispute;
pub mod arbiter;

pub use auto_create::AutoCreatePersona;
pub use auto_resolve::AutoResolvePersona;
pub use auto_dispute::AutoDisputePersona;
pub use arbiter::ArbiterPersona;
