# Quickstart for Integrating with UMA Optimistic Oracle V3

<a href="https://docs.uma.xyz/developers/optimistic-oracle"><img alt="OO" src="https://miro.medium.com/v2/resize:fit:1400/1*hLSl9M87P80A1pZ9vuTvyA.gif" width=600></a>

This repository contains example contracts and tests for integrating with the UMA Optimistic Oracle V3.
The primary contract example is `SourceAsserter.sol`, which allows users to:

1. Define "topics" with a description, duration, and a reward amount in a specific ERC20 token.
2. "Assert" data sources (URLs with descriptions and labels) under these topics. These assertions are secured by UMA's Optimistic Oracle V3.
3. If an assertion is successfully validated by UMA (i.e., not disputed or a dispute is resolved in favor of the asserter), the asserter receives the specified reward.

## Documentation 📚

Full documentation on how to build, test, deploy and interact with the example contracts in this repository are
documented [here](https://docs.uma.xyz/developers/optimistic-oracle).

This project uses [Foundry](https://getfoundry.sh). See the [book](https://book.getfoundry.sh/getting-started/installation.html)
for instructions on how to install and use Foundry.

## Getting Started 👩‍💻

### Install dependencies 👷‍♂️

On Linux and macOS Foundry toolchain can be installed with:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

In case there was a prior version of Foundry installed, it is advised to update it with `foundryup` command.

Other installation methods are documented [here](https://book.getfoundry.sh/getting-started/installation).

Forge manages dependencies using [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) by default, which
is also the method used in this repository. To install dependencies, run:

```bash
forge install
```

### Compile the contracts 🏗

Compile the contracts with:

```bash
forge build
```

### Run the tests 🧪

Test the example contracts with:

```bash
forge test
```

## Deploying SourceAsserter to Sepolia Testnet 🚀

The `SourceAsserter.sol` contract is designed to be deployed to a network where UMA V3 contracts are available, such as Sepolia.
A deployment script `script/DeploySourceAsserterSepolia.s.sol` is provided.

### Environment Variables for Sepolia Deployment

Before running the deployment script, ensure the following environment variables are set:

-   `SEPOLIA_RPC_URL`: URL of your Sepolia RPC node (e.g., `https://1rpc.io/sepolia` or from Alchemy, Infura).
-   `PRIVATE_KEY`: The private key of the account you wish to use for deployment. This account will be the owner of the deployed `SourceAsserter` contract and will need Sepolia ETH for gas.
-   `ETHERSCAN_API_KEY`: Your Etherscan API key, required for automatic contract verification on Sepolia Etherscan.

Example:

```bash
export SEPOLIA_RPC_URL="https://your-sepolia-rpc-url"
export PRIVATE_KEY="your_deployer_private_key_hex"
export ETHERSCAN_API_KEY="your_etherscan_api_key"
```

### Deployment Command

Once the environment variables are set, deploy and verify the `SourceAsserter` contract using the following command from the root of the project:

```bash
forge script script/DeploySourceAsserterSepolia.s.sol:DeploySourceAsserterSepolia \
  --rpc-url $SEPOLIA_RPC_URL \
  --fork-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

This script will:

1. Connect to the Sepolia network.
2. Use your private key to deploy the `SourceAsserter` contract.
3. Dynamically fetch the `defaultCurrency` from the official UMA OptimisticOracleV3 contract on Sepolia. This currency will be used for bonds in `assertSource` calls.
4. Link the `SourceAsserter` to the official UMA Finder and OptimisticOracleV3 contracts on Sepolia, and the pre-specified `RewardERC20` token.
5. Attempt to verify the deployed contract on Sepolia Etherscan.
6. Print the deployed contract address and important information for interaction.

Please see the console output of the script for the deployed contract address and next steps regarding token approvals and contract interactions.

## Running the Simple UI Locally 🖥️

A basic web interface is provided in the `ui/` directory to interact with a deployed `SourceAsserter` contract on the Sepolia testnet.

### Prerequisites

1.  A web browser with an EIP-1193 compatible wallet (e.g., MetaMask).
2.  The `SourceAsserter` contract must be deployed to the Sepolia testnet (see deployment instructions above).

### Configuration

1.  **Update Contract Addresses in `ui/app.js`:**
    Open `ui/app.js` and update the following constants:

    -   `SOURCE_ASSERTER_ADDRESS`: Replace `"YOUR_DEPLOYED_SOURCE_ASSERTER_ADDRESS"` (or the current example address) with the actual address of your deployed `SourceAsserter` contract on Sepolia.
    -   `REWARD_TOKEN_ADDRESS`: Ensure this matches the ERC20 token address you intend to use for rewards. The example address is `0x43F532D678b6a1587BE989a50526F89428f68315`.
    -   `BOND_CURRENCY_ADDRESS`: This should match the `DEFAULT_CURRENCY` used in your deployment script (e.g., `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` for Sepolia WETH, which is what the deployment script currently uses).

2.  **Ensure ABIs are present:** The `ui/abis/` directory should contain:
    -   `SourceAsserter.json` (from `out/SourceAsserter.sol/SourceAsserter.json` after `forge build`)
    -   `OptimisticOracleV3.json` (from `lib/protocol/packages/core/artifacts/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol/OptimisticOracleV3Interface.json`)
    -   `ERC20.json` (a standard ERC20 ABI)

### Running the UI

1.  Navigate to the `ui/` directory in your terminal:
    ```bash
    cd ui
    ```
2.  Start a simple HTTP server. If you have Python 3 installed:
    ```bash
    python -m http.server 8000
    ```
    (Or use any other static file server, like VS Code's Live Server extension).
3.  Open your web browser and go to `http://localhost:8000`.
4.  Connect your wallet (ensure it's set to the Sepolia network).
5.  You can now interact with the `SourceAsserter` contract to initialize topics and assert sources.

## Contracts

The following UMA contract addresses on Sepolia are used by the `SourceAsserter` and its deployment script:

-   **Finder**: `0xf4C48eDAd256326086AEfbd1A53e1896815F8f13`
-   **OptimisticOracleV3**: `0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944`
-   **RewardERC20 (Example)**: `0xc8fff6BBfc93e912B0012716Cf4573C2F7A9B974` (This is an example token; you can use any ERC20 token as a reward. The deployer of `SourceAsserter` must ensure it has these tokens to fund topics, or topic creators must have them.)
-   **Sepolia RPC (Example for reference)**: `https://1rpc.io/sepolia` (The script uses the `SEPOLIA_RPC_URL` environment variable).
