// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/SourceAsserter.sol";
// Interface to interact with the OptimisticOracleV3 to get its default currency
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";

contract DeploySourceAsserterSepolia is Script {
    function run() external {
        // Load deployer private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // Alternatively, to use a mnemonic:
        // string memory mnemonic = vm.envString("MNEMONIC");
        // uint256 deployerPrivateKey = vm.deriveKey(mnemonic, "m/44'/60'/0'/0/0"); // Example derivation path

        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("--- Deployment ---");
        console.log("Deployer address:", deployerAddress);
        console.log(
            "Deployer ETH balance:",
            deployerAddress.balance / 1e18,
            "ETH"
        );

        // Determine ECP Comment Manager address based on chain ID
        uint256 currentChainId = block.chainid;
        address ecpCommentManager;
        address ecpAddress = 0x519D00E2C60BD598a8c234785216A3037b09F0CF;
        address UMA_FINDER = 0xfF4Ec014E3CBE8f64a95bb022F1623C6e456F7dB;
        address UMA_OOV3 = 0x0F7fC5E6482f096380db6158f978167b57388deE;
        address REWARD_TOKEN = 0xe55E9C1bf81a6ABAD109881B999E5272F5195892;
        address DEFAULT_CURRENCY = 0x7E6d9618Ba8a87421609352d6e711958A97e2512;

        console.log("Current Chain ID for deployment:", currentChainId);

        if (currentChainId == 84532) {
            // Base Sepolia Chain ID
            ecpCommentManager = ecpAddress;
            console.log("Using ECP for Base Sepolia:", ecpCommentManager);
        } else {
            ecpCommentManager = address(0); // Default to address(0) if not Base Sepolia
            UMA_FINDER = 0xf4C48eDAd256326086AEfbd1A53e1896815F8f13;
            UMA_OOV3 = 0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944;
            REWARD_TOKEN = 0x43F532D678b6a1587BE989a50526F89428f68315;
            DEFAULT_CURRENCY = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
            console.log(
                "ECP not configured for this chain (Chain ID:",
                currentChainId,
                "). Setting CommentManager to address(0)."
            );
        }

        vm.startBroadcast(deployerPrivateKey);

        address bondCurrency = DEFAULT_CURRENCY;
        console.log(
            "UMA OOv3 Default Bond Currency (for bonds):",
            bondCurrency
        );

        // ecpCommentManager is now set conditionally above
        // The console log for its value is also handled above.

        // 2. Deploy SourceAsserter
        // The constructor arguments are:
        // address _finder,
        // address _currency (for bonds),
        // address _optimisticOracleV3,
        // address _rewardToken
        // address _commentManager
        SourceAsserter sourceAsserter = new SourceAsserter(
            UMA_FINDER,
            bondCurrency, // Fetched dynamically
            UMA_OOV3,
            REWARD_TOKEN, // Your specified reward token
            ecpCommentManager // Conditionally set ECP address
        );
        console.log("SourceAsserter deployed at:", address(sourceAsserter));

        vm.stopBroadcast();

        console.log("--- Deployment Summary ---");
        console.log("SourceAsserter address:", address(sourceAsserter));
        console.log("Using UMA Finder:", UMA_FINDER);
        console.log("Using UMA OptimisticOracleV3:", UMA_OOV3);
        console.log("Using Bond Currency (from OOv3):", bondCurrency);
        console.log("Using Reward Token (pre-existing):", REWARD_TOKEN);
        console.log(
            "Using Ethereum Comments Protocol (ECP) Manager:",
            ecpCommentManager
        );
        console.log("---------------------------");
        console.log("Important Next Steps:");
        console.log(
            "1. The SourceAsserter contract is owned by:",
            deployerAddress,
            "(the deployer)."
        );
        console.log(
            "   This owner can add new labels using `sourceAsserter.addLabel(string)` if the defaults are not sufficient."
        );
        console.log("2. For `initializeTopic` calls:");
        console.log(
            "   - The caller (topic creator) must possess the Reward Token (%s).",
            REWARD_TOKEN
        );
        console.log(
            "   - The caller must approve the SourceAsserter contract (%s) to spend their Reward Tokens for the `sourceReward` amount.",
            address(sourceAsserter)
        );
        console.log("3. For `assertSource` calls:");
        console.log(
            "   - The caller (asserter) must possess the Bond Currency (%s).",
            bondCurrency
        );
        console.log(
            "   - The caller must approve the SourceAsserter contract (%s) to spend their Bond Currency for the UMA bond amount.",
            address(sourceAsserter)
        );
        console.log(
            "4. Verify contract on Etherscan: https://sepolia.etherscan.io/address/%s#code",
            address(sourceAsserter)
        );
    }
}
