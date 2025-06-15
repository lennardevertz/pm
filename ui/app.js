// // --- CONFIGURATION ---
const SOURCE_ASSERTER_ADDRESS = "0x4aa59dAded7c781b46Aa04acb329861285dFaCd6"; // Replace with your deployed contract address
const UMA_OOV3_ADDRESS = "0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944"; // Sepolia OOv3
const REWARD_TOKEN_ADDRESS = "0x43F532D678b6a1587BE989a50526F89428f68315"; // Sepolia Example Reward Token
const BOND_CURRENCY_ADDRESS = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"; // Sepolia USDC (this is the DEFAULT_CURRENCY from your deploy script)
const SEPOLIA_CHAIN_ID = "0xaa36a7"; // 11155111 in hex
const CONTRACT_CREATION_BLOCK = 8519497; // Block when SourceAsserter was created
const MAX_RPC_QUERY_RANGE = 5000; // Max number of blocks to query in a single RPC call (as per user feedback)

// --- CONFIGURATION BASE ---
// const SOURCE_ASSERTER_ADDRESS = "0x08DAA69f088f2a89c1E54403739f102768e64979"; // Replace with your deployed contract address
// const UMA_OOV3_ADDRESS = "0x0F7fC5E6482f096380db6158f978167b57388deE"; // Sepolia OOv3
// const REWARD_TOKEN_ADDRESS = "0xe55E9C1bf81a6ABAD109881B999E5272F5195892"; // Sepolia Example Reward Token
// const BOND_CURRENCY_ADDRESS = "0x7E6d9618Ba8a87421609352d6e711958A97e2512"; // Sepolia USDC (this is the DEFAULT_CURRENCY from your deploy script)
// const SEPOLIA_CHAIN_ID = "0x14a34"; // 84532 in hex
// const CONTRACT_CREATION_BLOCK = 26901190; // Block when SourceAsserter was created
// const MAX_RPC_QUERY_RANGE = 5000; // Max number of blocks to query in a single RPC call (as per user feedback)

// --- APPLICATION STATE ---
let provider;
let signer;
let sourceAsserterContract;
let optimisticOracleContract;
let rewardTokenContract;
let bondCurrencyContract;
let sourceAsserterAbi;
let ooV3Abi;
let erc20Abi;

// --- DOM ELEMENTS ---
const connectWalletBtn = document.getElementById("connectWalletBtn");
const connectedAccountEl = document.getElementById("connectedAccount");
const networkNameEl = document.getElementById("networkName");
const statusMessageEl = document.getElementById("statusMessage");

const initializeTopicBtn = document.getElementById("initializeTopicBtn");
const topicTitleEl = document.getElementById("topicTitle");
const topicDescriptionEl = document.getElementById("topicDescription");
const topicOriginUrlEl = document.getElementById("topicOriginUrl");
const topicDurationEl = document.getElementById("topicDuration");
const topicRewardEl = document.getElementById("topicReward");

const assertSourceBtn = document.getElementById("assertSourceBtn");
const assertTopicIdEl = document.getElementById("assertTopicId");
const assertLabelEl = document.getElementById("assertLabel");
const assertUrlEl = document.getElementById("assertUrl");
const assertSourceDescEl = document.getElementById("assertSourceDesc");

const refreshTopicsBtn = document.getElementById("refreshTopicsBtn");
const topicsListEl = document.getElementById("topicsList");
const refreshSourcesBtn = document.getElementById("refreshSourcesBtn");
const filterTopicIdEl = document.getElementById("filterTopicId");
const sourcesListEl = document.getElementById("sourcesList");

// --- HELPER FUNCTIONS ---
function showStatus(message, isError = false) {
    statusMessageEl.textContent = message;
    statusMessageEl.className = isError ? "error" : "success";
    statusMessageEl.classList.remove("hidden");
    setTimeout(() => {
        statusMessageEl.classList.add("hidden");
        statusMessageEl.textContent = ""; // Clear message after hiding
    }, 5000);
}

async function loadAbis() {
    try {
        const saRes = await fetch("./abis/SourceAsserter.json");
        if (!saRes.ok)
            throw new Error(
                `Failed to fetch SourceAsserter.json: ${saRes.statusText}`
            );
        sourceAsserterAbi = (await saRes.json()).abi; // Assuming the ABI is nested under an "abi" key

        const ooRes = await fetch("./abis/OptimisticOracleV3.json");
        if (!ooRes.ok)
            throw new Error(
                `Failed to fetch OptimisticOracleV3.json: ${ooRes.statusText}`
            );
        ooV3Abi = await ooRes.json(); // Corrected: The JSON file IS the ABI array

        const erc20Res = await fetch("./abis/ERC20.json");
        if (!erc20Res.ok)
            throw new Error(
                `Failed to fetch ERC20.json: ${erc20Res.statusText}`
            );
        erc20Abi = await erc20Res.json(); // ERC20 ABI might be a direct array

        console.log("ABIs loaded");
        if (!sourceAsserterAbi || !ooV3Abi || !erc20Abi) {
            throw new Error("One or more ABIs did not load correctly.");
        }
    } catch (error) {
        console.error("Error loading ABIs:", error);
        showStatus(
            `Error loading contract ABIs: ${error.message}. Check console and ABI paths.`,
            true
        );
    }
}

async function connectWallet() {
    if (typeof window.ethereum === "undefined") {
        showStatus("MetaMask is not installed!", true);
        return;
    }
    try {
        await window.ethereum.request({method: "eth_requestAccounts"});
        provider = new ethers.providers.Web3Provider(window.ethereum);
        signer = provider.getSigner();
        const userAddress = await signer.getAddress();
        connectedAccountEl.textContent = userAddress;

        const network = await provider.getNetwork();
        console.log(network);
        networkNameEl.textContent = `${network.name} (Chain ID: ${network.chainId})`;

        if (network.chainId !== parseInt(SEPOLIA_CHAIN_ID, 16)) {
            showStatus(
                `Please connect to Sepolia network (Chain ID: ${parseInt(
                    SEPOLIA_CHAIN_ID,
                    16
                )})`,
                true
            );
            return;
        }

        if (!sourceAsserterAbi || !ooV3Abi || !erc20Abi) {
            showStatus("ABIs not loaded. Cannot initialize contracts.", true);
            return;
        }

        sourceAsserterContract = new ethers.Contract(
            SOURCE_ASSERTER_ADDRESS,
            sourceAsserterAbi,
            signer
        );
        optimisticOracleContract = new ethers.Contract(
            UMA_OOV3_ADDRESS,
            ooV3Abi,
            signer
        );
        rewardTokenContract = new ethers.Contract(
            REWARD_TOKEN_ADDRESS,
            erc20Abi,
            signer
        );
        bondCurrencyContract = new ethers.Contract(
            BOND_CURRENCY_ADDRESS,
            erc20Abi,
            signer
        );

        showStatus("Wallet connected successfully!");
        loadTopics();
        loadSources();
    } catch (error) {
        console.error("Wallet connection error:", error);
        showStatus(`Error connecting wallet: ${error.message || error}`, true);
    }
}

// --- CONTRACT INTERACTIONS ---

async function initializeTopic() {
    if (!signer || !sourceAsserterContract || !rewardTokenContract) {
        showStatus(
            "Please connect your wallet and ensure contracts are initialized.",
            true
        );
        return;
    }
    const title = topicTitleEl.value;
    const description = topicDescriptionEl.value;
    const originUrl = topicOriginUrlEl.value;
    const duration = parseInt(topicDurationEl.value);
    const rewardAmountStr = topicRewardEl.value;

    if (!title || !description || isNaN(duration) || !rewardAmountStr) {
        showStatus(
            "Please fill all required topic fields (Title, Description, Duration, Reward).",
            true
        );
        return;
    }

    try {
        const rewardDecimals = await rewardTokenContract.decimals();
        const rewardAmount = ethers.utils.parseUnits(
            rewardAmountStr,
            rewardDecimals
        );

        showStatus("Approving reward token spend...");
        const approveTx = await rewardTokenContract.approve(
            SOURCE_ASSERTER_ADDRESS,
            rewardAmount
        );
        await approveTx.wait();
        showStatus("Approval successful. Initializing topic...");

        const tx = await sourceAsserterContract.initializeTopic(
            title,
            description,
            originUrl,
            duration,
            rewardAmount
        );
        showStatus(`Initializing topic... TX: ${tx.hash}`);
        const receipt = await tx.wait();
        const topicId = receipt.events?.find(
            (e) => e.event === "TopicInitialized"
        )?.args?.topicId;
        showStatus(
            `Topic initialized successfully! Topic ID: ${topicId}. TX: ${receipt.transactionHash}`
        );
        loadTopics(); // Refresh list
    } catch (error) {
        console.error("Initialize topic error:", error);
        showStatus(
            `Error initializing topic: ${
                error?.data?.message || error.message || error
            }`,
            true
        );
    }
}

async function assertSource() {
    if (
        !signer ||
        !sourceAsserterContract ||
        !optimisticOracleContract ||
        !bondCurrencyContract
    ) {
        showStatus(
            "Please connect your wallet and ensure contracts are initialized.",
            true
        );
        return;
    }
    const topicId = assertTopicIdEl.value;
    const label = assertLabelEl.value;
    const url = assertUrlEl.value;
    const sourceDesc = assertSourceDescEl.value;

    if (!topicId || !label || /* !url */ !sourceDesc) {
        showStatus(
            "Please fill Topic ID, Label, and Source Description. URL is optional.",
            true
        );
        return;
    }

    try {
        const minBond = await optimisticOracleContract.getMinimumBond(
            BOND_CURRENCY_ADDRESS
        );
        const bondDecimals = await bondCurrencyContract.decimals();
        showStatus(
            `Minimum bond required: ${ethers.utils.formatUnits(
                minBond,
                bondDecimals
            )} BondToken`
        );

        showStatus("Approving bond currency spend...");
        const approveTx = await bondCurrencyContract.approve(
            SOURCE_ASSERTER_ADDRESS,
            minBond
        );
        await approveTx.wait();
        showStatus("Approval successful. Asserting source...");

        const tx = await sourceAsserterContract.assertSource(
            topicId,
            label,
            url,
            sourceDesc
        );
        showStatus(`Asserting source... TX: ${tx.hash}`);
        const receipt = await tx.wait();
        const assertionId = receipt.events?.find(
            (e) => e.event === "TopicSourceAdded"
        )?.args?.assertionId;
        showStatus(
            `Source asserted successfully! Assertion ID: ${assertionId}. TX: ${receipt.transactionHash}`
        );
        loadSources(); // Refresh list
    } catch (error) {
        console.error("Assert source error:", error);
        showStatus(
            `Error asserting source: ${
                error?.data?.message || error.message || error
            }`,
            true
        );
    }
}

async function loadTopics() {
    if (!sourceAsserterContract || !provider) return;
    topicsListEl.innerHTML = "<li>Loading topics...</li>";
    try {
        const latestBlock = await provider.getBlockNumber();
        const fromBlock = Math.max(
            CONTRACT_CREATION_BLOCK,
            latestBlock - MAX_RPC_QUERY_RANGE
        );

        const filter = sourceAsserterContract.filters.TopicInitialized();
        const events = await sourceAsserterContract.queryFilter(
            filter,
            fromBlock,
            latestBlock
        );
        topicsListEl.innerHTML = "";
        if (events.length === 0) {
            topicsListEl.innerHTML = `<li>No topics found (queried from block ${fromBlock} to ${latestBlock}).</li>`;
            return;
        }
        if (!rewardTokenContract) {
            showStatus("Reward token contract not initialized.", true);
            topicsListEl.innerHTML =
                "<li>Error: Reward token contract not ready.</li>";
            return;
        }
        const rewardDecimals = await rewardTokenContract.decimals();
        events.reverse().forEach((event) => {
            const topic = event.args;
            const li = document.createElement("li");
            li.className = "topic-item";

            const rewardStr =
                topic.sourceReward &&
                typeof topic.sourceReward.toString === "function"
                    ? ethers.utils.formatUnits(
                          topic.sourceReward,
                          rewardDecimals
                      )
                    : "Data unavailable";

            const startTimeStr =
                topic.startTime &&
                typeof topic.startTime.toNumber === "function"
                    ? new Date(
                          topic.startTime.toNumber() * 1000
                      ).toLocaleString()
                    : "N/A";

            const endTimeInSeconds =
                topic.endTime && typeof topic.endTime.toNumber === "function"
                    ? topic.endTime.toNumber()
                    : 0;
            const endTimeStr =
                endTimeInSeconds > 0
                    ? new Date(endTimeInSeconds * 1000).toLocaleString()
                    : "N/A";

            // Calculate current status
            const currentTimeInSeconds = Math.floor(Date.now() / 1000);
            let statusIndicatorHtml = "";
            if (endTimeInSeconds > 0) {
                if (currentTimeInSeconds < endTimeInSeconds) {
                    statusIndicatorHtml =
                        '<span class="status-indicator active"></span><strong style="color: #28a745;">Active</strong>';
                } else {
                    statusIndicatorHtml =
                        '<span class="status-indicator expired"></span><strong style="color: #dc3545;">Expired</strong>';
                }
            } else {
                statusIndicatorHtml = "<span>Status Unknown</span>"; // Should not happen with valid data
            }

            const title = topic.title || "N/A";
            const description = topic.description || "N/A";
            const originUrl = topic.originUrl || ""; // Event emits 'originUrl'

            li.innerHTML = `
                <strong>ID:</strong> ${topic.topicId || "N/A"}<br>
                <strong>Status:</strong> ${statusIndicatorHtml}<br> <!-- Added Status Line -->
                <strong>Title:</strong> ${title}<br>
                <strong>Description:</strong> ${description}<br>
                ${
                    originUrl
                        ? `<strong>Origin URL:</strong> <a href="${originUrl}" target="_blank" rel="noopener noreferrer">${originUrl}</a><br>`
                        : "<strong>Origin URL:</strong> N/A<br>"
                }
                <strong>Reward:</strong> ${rewardStr} APPR<br>
                <strong>Start:</strong> ${startTimeStr}<br>
                <strong>End:</strong> ${endTimeStr}
            `;
            topicsListEl.appendChild(li);
        });
    } catch (error) {
        console.error("Error loading topics:", error);
        topicsListEl.innerHTML = "<li>Error loading topics.</li>";
        showStatus(`Error loading topics: ${error.message}`, true);
    }
}

const statusEnum = ["Pending", "Valid", "Disputed", "Rejected"];

async function loadSources() {
    if (!sourceAsserterContract || !provider) return;
    sourcesListEl.innerHTML = "<li>Loading sources...</li>";
    try {
        const latestBlock = await provider.getBlockNumber();
        const fromBlock = Math.max(
            CONTRACT_CREATION_BLOCK,
            latestBlock - MAX_RPC_QUERY_RANGE
        );

        const sourceAddedFilter =
            sourceAsserterContract.filters.TopicSourceAdded();
        const addedEvents = await sourceAsserterContract.queryFilter(
            sourceAddedFilter,
            fromBlock,
            latestBlock
        );
        sourcesListEl.innerHTML = "";

        if (addedEvents.length === 0) {
            sourcesListEl.innerHTML = `<li>No sources found (queried from block ${fromBlock} to ${latestBlock}).</li>`;
            return;
        }

        const filterTopic = filterTopicIdEl.value.trim();
        let sourcesDisplayed = 0;

        for (const event of addedEvents.reverse()) {
            const assertionId = event.args.assertionId;
            const topicIdFromEvent = event.args.topicId;

            if (
                filterTopic &&
                topicIdFromEvent.toLowerCase() !== filterTopic.toLowerCase()
            ) {
                continue;
            }

            const sourceData = await sourceAsserterContract.getSource(
                assertionId
            );
            const li = document.createElement("li");
            li.className = "source-item";
            // The label in sourceData.label is a bytes32 hash. We can't decode it back to string easily.
            // We'll display the hash or you can modify to store/retrieve original label string.
            li.innerHTML = `
                <strong>Assertion ID:</strong> ${assertionId}<br>
                <strong>Topic ID:</strong> ${sourceData.topicId}<br>
                <strong>Asserter:</strong> ${sourceData.asserter}<br>
                <strong>Label Hash:</strong> ${sourceData.label}<br>
                <strong>URL:</strong> <a href="${
                    sourceData.url
                }" target="_blank" rel="noopener noreferrer">${
                sourceData.url
            }</a><br>
                <strong>Description:</strong> ${ethers.utils.toUtf8String(
                    sourceData.description
                )}<br>
                <strong>Status:</strong> ${statusEnum[sourceData.status]}<br>
                <strong>Created At:</strong> ${new Date(
                    sourceData.createdAt.toNumber() * 1000
                ).toLocaleString()}<br>
                ${
                    sourceData.disputedAt.toNumber() > 0
                        ? `<strong>Disputed At:</strong> ${new Date(
                              sourceData.disputedAt.toNumber() * 1000
                          ).toLocaleString()}<br>`
                        : ""
                }
                ${
                    sourceData.status === statusEnum.indexOf("Pending")
                        ? `<button onclick="disputeAssertion('${assertionId}')">Dispute</button>`
                        : ""
                }
                ${
                    (sourceData.status === statusEnum.indexOf("Pending") ||
                        sourceData.status === statusEnum.indexOf("Disputed")) &&
                    sourceData.disputedAt.toNumber() === 0 // Only show settle if not yet disputed or if OO allows settling disputed items
                        ? `<button onclick="settleAssertion('${assertionId}')">Settle</button>`
                        : ""
                }
                ${
                    // Allow settling a disputed item once it's past its liveness + dispute period
                    sourceData.status === statusEnum.indexOf("Disputed")
                        ? `<button onclick="settleAssertion('${assertionId}')">Settle Disputed</button>`
                        : ""
                }
            `;
            sourcesListEl.appendChild(li);
            sourcesDisplayed++;
        }
        if (sourcesDisplayed === 0 && filterTopic) {
            sourcesListEl.innerHTML =
                "<li>No sources found for this Topic ID.</li>";
        } else if (sourcesDisplayed === 0) {
            sourcesListEl.innerHTML = `<li>No sources found (queried from block ${fromBlock} to ${latestBlock}).</li>`;
        }
    } catch (error) {
        console.error("Error loading sources:", error);
        sourcesListEl.innerHTML = "<li>Error loading sources.</li>";
        showStatus(`Error loading sources: ${error.message}`, true);
    }
}

async function disputeAssertion(assertionId) {
    if (!signer || !optimisticOracleContract || !bondCurrencyContract) {
        showStatus(
            "Please connect your wallet and ensure contracts are initialized.",
            true
        );
        return;
    }
    showStatus(`Attempting to dispute assertion ${assertionId}...`);
    try {
        const assertion = await optimisticOracleContract.getAssertion(
            assertionId
        );
        const bondAmount = assertion.bond;
        const bondDecimals = await bondCurrencyContract.decimals();

        showStatus(
            `Dispute bond required: ${ethers.utils.formatUnits(
                bondAmount,
                bondDecimals
            )} BondToken`
        );

        showStatus("Approving bond currency for dispute...");
        const approveTx = await bondCurrencyContract.approve(
            UMA_OOV3_ADDRESS,
            bondAmount
        );
        await approveTx.wait();
        showStatus("Approval successful. Disputing assertion...");

        const tx = await optimisticOracleContract.disputeAssertion(
            assertionId,
            await signer.getAddress()
        );
        showStatus(`Disputing assertion... TX: ${tx.hash}`);
        await tx.wait();
        showStatus(`Assertion ${assertionId} disputed successfully!`);
        loadSources();
    } catch (error) {
        console.error("Dispute error:", error);
        showStatus(
            `Error disputing: ${error?.data?.message || error.message}`,
            true
        );
    }
}

async function settleAssertion(assertionId) {
    if (!signer || !optimisticOracleContract) {
        showStatus("Please connect your wallet first.", true);
        return;
    }
    showStatus(`Attempting to settle assertion ${assertionId}...`);
    try {
        const tx = await optimisticOracleContract.settleAndGetAssertionResult(
            assertionId
        );
        showStatus(`Settling assertion... TX: ${tx.hash}`);
        const receipt = await tx.wait();
        showStatus(
            `Assertion ${assertionId} settlement process initiated/completed. TX: ${receipt.transactionHash}`
        );
        loadSources();
    } catch (error) {
        console.error("Settle error:", error);
        showStatus(
            `Error settling: ${error?.data?.message || error.message}`,
            true
        );
    }
}

// --- EVENT LISTENERS ---
window.addEventListener("load", async () => {
    await loadAbis(); // Load ABIs first
    connectWalletBtn.addEventListener("click", connectWallet);
    initializeTopicBtn.addEventListener("click", initializeTopic);
    assertSourceBtn.addEventListener("click", assertSource);
    refreshTopicsBtn.addEventListener("click", loadTopics);
    refreshSourcesBtn.addEventListener("click", loadSources);

    if (window.ethereum) {
        window.ethereum.on("accountsChanged", (accounts) => {
            if (accounts.length > 0) {
                connectWallet();
            } else {
                connectedAccountEl.textContent = "Not Connected";
                networkNameEl.textContent = "N/A";
                showStatus("Wallet disconnected.", true);
            }
        });
        window.ethereum.on("chainChanged", (chainId) => {
            connectWallet();
        });
    }
});
