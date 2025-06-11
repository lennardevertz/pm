// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uma/core/contracts/common/implementation/AddressWhitelist.sol";
import "@uma/core/contracts/data-verification-mechanism/implementation/Constants.sol";
import "@uma/core/contracts/data-verification-mechanism/interfaces/FinderInterface.sol";
import "@uma/core/contracts/optimistic-oracle-v3/implementation/ClaimData.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3Interface.sol";
import "@uma/core/contracts/optimistic-oracle-v3/interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./LabelRegistry.sol";
import "./ECPHelper.sol";

// --- Custom Errors ---
error UnsupportedCurrency();
error EmptyDescription();
error TopicAlreadyExists();
error TopicDoesNotExist();
error TopicExpired();
error InvalidLabel();
error NotOptimisticOracle();
error ChannelIdAlreadySet();
// --- End Custom Errors ---

contract SourceAsserter is
    OptimisticOracleV3CallbackRecipientInterface,
    LabelRegistry,
    Ownable
{
    using SafeERC20 for IERC20;

    enum Status {
        Pending,
        Valid,
        Disputed,
        Rejected
    }

    struct Topic {
        bytes title; // Title of the topic
        bytes description; // Brief description of this topic
        bytes originUrl; // Original source of the topic.
        uint256 startTime; // When assertions become valid
        uint256 endTime; // When assertions expire
        bytes32[] sourceAssertions; // List of UMA assertionIds submitted for this topic
        address creator;
        uint256 sourceReward;
        bytes32 ecpCommentId; // ECP Comment ID for this topic
    }

    struct Source {
        address asserter; // Who called assertSource(...)
        bytes32 topicId; // Which topic this source belongs to
        bytes32 label; // keccak256(abi.encodePacked(labelString)) — must be in LabelRegistry
        string url; // URL of the data source (no fixed length)
        bytes description; // Freeform description text
        Status status; // Pending until UMA resolves, then Valid or Disputed
        uint256 createdAt; // Timestamp of when the source was asserted
        uint256 disputedAt; // Timestamp of when the source was disputed, 0 if not disputed
        bytes32 ecpCommentId; // ECP Comment ID for this source
    }

    mapping(bytes32 => Topic) public topics; // topicId => Topic
    mapping(bytes32 => Source) public sources; // assertionId => Source

    FinderInterface public immutable finder;
    IERC20 public immutable currency; // Currency used for UMA bonds (e.g. USDC)
    IERC20 public immutable rewardToken;
    OptimisticOracleV3Interface public immutable oo;
    ICommentManager public immutable commentManager; // Use namespaced interface
    uint64 public constant assertionLiveness = 120; // 2 hours -> (120 seconds for testing, should be 2 hours (7200))
    bytes32 public immutable defaultIdentifier;
    uint256 public ecpChannelId;

    event TopicInitialized(
        bytes32 indexed topicId,
        string title,
        string description,
        string originUrl,
        uint256 startTime,
        uint256 endTime,
        uint256 sourceReward
    );
    event TopicSourceAdded(
        bytes32 indexed topicId,
        bytes32 indexed assertionId
    );
    event SourceResolved(bytes32 indexed assertionId, bool assertedTruthfully);
    event EcpChannelIdUpdated(uint256 newChannelId);

    constructor(
        address _finder,
        address _currency,
        address _optimisticOracleV3,
        address _rewardToken,
        address _commentManager
    ) Ownable() {
        finder = FinderInterface(_finder);
        if (!_getCollateralWhitelist().isOnWhitelist(_currency)) {
            revert UnsupportedCurrency();
        }
        currency = IERC20(_currency);
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();
        rewardToken = IERC20(_rewardToken);
        ecpChannelId = ECPHelper.DEFAULT_CHANNEL_ID; // Initialize with default
        commentManager = ICommentManager(_commentManager); // Use namespaced interface
    }

    /// @notice Create a new topic.
    /// @param _description  Short description of what this topic is about.
    /// @param duration      How long (in seconds) new sources can be submitted before “expiry.”
    function initializeTopic(
        string memory _title,
        string memory _description,
        string memory _originUrl,
        uint256 duration,
        uint256 _sourceReward
    ) public returns (bytes32 topicId) {
        if (bytes(_description).length == 0) {
            revert EmptyDescription();
        }
        uint256 start = block.timestamp;
        topicId = keccak256(
            abi.encodePacked(start, _title, _description, _originUrl)
        );
        if (topics[topicId].startTime != 0) {
            revert TopicAlreadyExists();
        }

        // Temporarily store topic data without ecpCommentId
        Topic memory newTopic = Topic({
            title: bytes(_title),
            description: bytes(_description),
            originUrl: bytes(_originUrl),
            startTime: start,
            endTime: start + duration,
            sourceAssertions: new bytes32[](0),
            creator: msg.sender,
            sourceReward: _sourceReward,
            ecpCommentId: bytes32(0) // Initialize, will be set below
        });

        // Post comment to ECP for the new topic
        string memory topicContent = string(
            abi.encodePacked(_title, " - ", _description)
        );
        if (bytes(_originUrl).length > 0) {
            topicContent = string(
                abi.encodePacked(topicContent, " (Origin: ", _originUrl, ")")
            );
        }
        // For a new topic, parentId is bytes32(0)
        bytes32 newTopicEcpCommentId = ECPHelper.postCommentAndGetId(
            commentManager,
            ecpChannelId,
            bytes32(0), // parentId
            topicContent,
            address(this)
        );
        newTopic.ecpCommentId = newTopicEcpCommentId; // Store the ECP comment ID

        topics[topicId] = newTopic; // Now store the complete topic data

        emit TopicInitialized(
            topicId,
            _title,
            _description,
            _originUrl,
            start,
            start + duration,
            _sourceReward
        );
    }

    /// @notice Submit a new “source” under a given topic, which UMA will verify.
    /// @param topicId      The topic to attach this source to (must exist and not be expired).
    /// @param label  A human‐readable label (e.g. "api", "news", "tweet")—hashed on‐chain.
    /// @param url         URL of the source (stored fully as string).
    /// @param sourceDesc   Freeform text explaining what the source is.
    function assertSource(
        bytes32 topicId,
        string memory label,
        string memory url,
        string memory sourceDesc
    ) public returns (bytes32 assertionId) {
        Topic storage topic = topics[topicId];
        if (topic.startTime == 0) {
            revert TopicDoesNotExist();
        }
        if (block.timestamp >= topic.endTime) {
            revert TopicExpired();
        }

        // 1) Hash the label string and check LabelRegistry
        bytes32 labelHash = keccak256(abi.encodePacked(label));
        if (!isValidLabel[labelHash]) {
            revert InvalidLabel();
        }

        // 2) Compute UMA's minimum bond in this currency
        uint256 bond = oo.getMinimumBond(address(currency));

        // 3) Pull that bond from the asserter
        currency.safeTransferFrom(msg.sender, address(this), bond);
        currency.safeApprove(address(oo), bond);

        // 4) Build UMA claim (embedding timestamp, topicId, url, description)
        bytes memory claim = _composeClaim(topicId, url, sourceDesc);

        // 5) Submit to UMA
        assertionId = oo.assertTruth(
            claim,
            msg.sender, // asserter
            address(this), // callback recipient
            address(0), // no sovereign security
            assertionLiveness,
            currency,
            bond,
            defaultIdentifier,
            bytes32(0)
        );

        // 6) Track it in both mappings
        topic.sourceAssertions.push(assertionId);

        // Temporarily store source data without ecpCommentId
        Source memory newSource = Source({
            asserter: msg.sender,
            topicId: topicId,
            label: labelHash,
            url: url,
            description: bytes(sourceDesc),
            status: Status.Pending,
            createdAt: block.timestamp,
            disputedAt: 0,
            ecpCommentId: bytes32(0) // Initialize, will be set below
        });

        // Post comment to ECP for the new source assertion
        string memory asserterAddressString = string(
            abi.encodePacked("0x", ClaimData.toUtf8BytesAddress(msg.sender))
        );
        string memory baseSourceContent = string(
            abi.encodePacked(
                sourceDesc,
                " (Asserted by: ",
                asserterAddressString,
                ")"
            )
        );
        string memory sourceCommentContent = baseSourceContent;
        if (bytes(url).length > 0) {
            // url is the source's URL parameter
            sourceCommentContent = string(
                abi.encodePacked(baseSourceContent, " (Source URL: ", url, ")")
            );
        }

        bytes32 newSourceEcpCommentId = ECPHelper.postCommentAndGetId(
            commentManager,
            ecpChannelId,
            topic.ecpCommentId, // Use the parent topic's ECP comment ID
            sourceCommentContent,
            address(this)
        );
        newSource.ecpCommentId = newSourceEcpCommentId; // Store the ECP comment ID

        sources[assertionId] = newSource; // Now store the complete source data

        emit TopicSourceAdded(topicId, assertionId);
    }

    /// @notice UMA calls this when an assertion's liveness ends (either undisputed or successfully verified).
    /// @param assertionId       The UMA-generated ID for this assertion.
    /// @param assertedTruthfully True if UMA/DVM agreed with the claim; false if disputed/lost.
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public override {
        if (msg.sender != address(oo)) {
            revert NotOptimisticOracle();
        }

        Source storage s = sources[assertionId];

        Topic storage t = topics[s.topicId];

        if (assertedTruthfully) {
            s.status = Status.Valid;
            rewardToken.safeTransferFrom(t.creator, s.asserter, t.sourceReward);
        } else {
            s.status = Status.Rejected;
        }

        // Leave the bond handling (slash/return) entirely to UMA’s DVM. We do not touch it here.

        // Post a comment to ECP indicating the resolution
        if (s.ecpCommentId != bytes32(0)) {
            // Only post if original source had an ECP comment
            string memory resolutionCommentContent;
            if (assertedTruthfully) {
                resolutionCommentContent = "Approved by UMA";
            } else {
                resolutionCommentContent = "Rejected by UMA";
            }
            ECPHelper.postCommentAndGetId(
                commentManager,
                ecpChannelId,
                s.ecpCommentId, // Parent is the original source's ECP comment ID
                resolutionCommentContent, // Content based on resolution
                address(this)
            );
        }
        emit SourceResolved(assertionId, assertedTruthfully);
    }

    /// @notice Called by UMA if someone disputes an active assertion.
    function assertionDisputedCallback(bytes32 assertionId) public override {
        if (msg.sender != address(oo)) {
            revert NotOptimisticOracle();
        }
        Source storage s = sources[assertionId];
        s.status = Status.Disputed;
        s.disputedAt = block.timestamp;

        // Post a comment to ECP indicating the dispute
        if (s.ecpCommentId != bytes32(0)) {
            // Only post if original source had an ECP comment
            ECPHelper.postCommentAndGetId(
                commentManager,
                ecpChannelId,
                s.ecpCommentId, // Parent is the original source's ECP comment ID
                "Disputed",
                address(this)
            );
        }
    }

    /// @notice Fetch all UMA-generated assertion IDs for a topic.
    function getTopic(bytes32 topicId) public view returns (Topic memory) {
        return topics[topicId];
    }

    /// @notice Fetch the Source struct (including final status) by its UMA assertionId.
    function getSource(
        bytes32 assertionId
    ) public view returns (Source memory) {
        return sources[assertionId];
    }

    /// @notice Allows the owner to set the ECP channel ID for future comments.
    function setEcpChannelId(uint256 _newChannelId) public onlyOwner {
        if (ecpChannelId != ECPHelper.DEFAULT_CHANNEL_ID) {
            revert ChannelIdAlreadySet();
        }
        ecpChannelId = _newChannelId;
        emit EcpChannelIdUpdated(_newChannelId);
    }

    function _getCollateralWhitelist()
        internal
        view
        returns (AddressWhitelist)
    {
        return
            AddressWhitelist(
                finder.getImplementationAddress(
                    OracleInterfaces.CollateralWhitelist
                )
            );
    }

    function _composeClaim(
        bytes32 topicId,
        string memory url,
        string memory sourceDesc
    ) internal view returns (bytes memory) {
        return
            abi.encodePacked(
                "As of timestamp ",
                ClaimData.toUtf8BytesUint(block.timestamp),
                ", source for topic 0x",
                ClaimData.toUtf8Bytes(topicId),
                ": ",
                url,
                " - ",
                sourceDesc
            );
    }
}
