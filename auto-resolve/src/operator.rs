use alloy::network::EthereumWallet;
use alloy::primitives::{Address, U256};
use alloy::providers::ProviderBuilder;
use alloy::signers::local::PrivateKeySigner;
use alloy::sol;
use anyhow::{Context, Result};
use std::str::FromStr;

sol! {
    #[allow(missing_docs)]
    #[sol(rpc)]
    contract Operator {
        function proposeResolution(uint256 marketId, uint8 winningOutcome) external;
        function marketCount() external view returns (uint256);
    }
}

pub struct OperatorClient {
    rpc_url: String,
    operator: Address,
    signer: PrivateKeySigner,
}

impl OperatorClient {
    pub async fn new(rpc_url: &str, operator_address: &str, private_key: &str) -> Result<Self> {
        let pk = private_key.trim_start_matches("0x");
        let signer: PrivateKeySigner = pk
            .parse()
            .context("parsing RESOLVER_PRIVATE_KEY as hex")?;
        let operator = Address::from_str(operator_address.trim_start_matches("0x"))
            .context("parsing OPERATOR_ADDRESS")?;
        Ok(Self {
            rpc_url: rpc_url.to_string(),
            operator,
            signer,
        })
    }

    pub fn signer_address(&self) -> Address {
        self.signer.address()
    }

    pub async fn propose_resolution(&self, market_id: u64, winning_outcome: u8) -> Result<String> {
        let wallet = EthereumWallet::from(self.signer.clone());
        let provider = ProviderBuilder::new()
            .with_recommended_fillers()
            .wallet(wallet)
            .on_http(self.rpc_url.parse().context("parsing RPC_URL")?);

        let contract = Operator::new(self.operator, provider);
        let pending = contract
            .proposeResolution(U256::from(market_id), winning_outcome)
            .send()
            .await
            .context("sending proposeResolution tx")?;
        let receipt = pending
            .get_receipt()
            .await
            .context("awaiting proposeResolution receipt")?;
        Ok(format!("{:?}", receipt.transaction_hash))
    }
}
