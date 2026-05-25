//! Reverb Markets-specific chi vocabulary. After the forager-as-library refactor, each
//! persona binary builds its own hello via `PersonaForagerBuilder`; this module exposes
//! only the product's chi constants for personas that subscribe to product-specific tones.

/// Reverb Markets-specific chis on top of the substrate's base vocabulary.
pub const MARKETS_CHIS: &[&str] = &[
    "market-created",
    "market-resolved",
    "dispute-filed",
    "dispute-ruled",
    "settlement-completed",
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn markets_chis_contains_lifecycle_tones() {
        assert!(MARKETS_CHIS.contains(&"market-created"));
        assert!(MARKETS_CHIS.contains(&"dispute-ruled"));
    }
}
