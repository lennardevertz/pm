// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "./common/CommonOptimisticOracleV3Test.sol";
import "../src/SourceAsserter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestRewardToken is ERC20 {
    constructor() ERC20("RewardToken", "RWD") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SourceAsserterTest is CommonOptimisticOracleV3Test {
    SourceAsserter public sourceAsserter;
    TestRewardToken public rewardToken;
    string public labelString = "api";
    bytes32 public labelHash = keccak256(abi.encodePacked("api"));
    string public url_ = "https://example.com/data.json";
    string public sourceDesc = "Test source description";
    uint256 public sourceReward = 50e18;
    string public defaultTitle = "Test Topic Title";
    string public defaultOriginUrl = "https://example.com/original-source";

    function setUp() public {
        _commonSetup();
        rewardToken = new TestRewardToken();
        rewardToken.mint(TestAddress.owner, 1_000e18);

        sourceAsserter = new SourceAsserter(
            address(finder),
            address(defaultCurrency),
            address(optimisticOracleV3),
            address(rewardToken),
            address(0)
        );

        vm.prank(TestAddress.owner);
        sourceAsserter.addLabel(labelString);
    }

    function test_RevertIf_InvalidTopic() public {
        vm.prank(TestAddress.account1);
        vm.expectRevert(TopicDoesNotExist.selector);
        sourceAsserter.assertSource(bytes32(0), labelString, url_, sourceDesc);
    }

    function test_RevertIf_ExpiredTopic() public {
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "A topic",
            defaultOriginUrl,
            1,
            sourceReward
        );

        vm.warp(block.timestamp + 2);
        vm.prank(TestAddress.account1);
        vm.expectRevert(TopicExpired.selector);
        sourceAsserter.assertSource(topicId, labelString, url_, sourceDesc);
    }

    function test_RevertIf_InvalidLabel() public {
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "Some topic",
            defaultOriginUrl,
            100,
            sourceReward
        );

        vm.prank(TestAddress.account1);
        vm.expectRevert(InvalidLabel.selector);
        sourceAsserter.assertSource(topicId, "notALabel", url_, sourceDesc);
    }

    function test_AssertionFlowAndRewardPayment() public {
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "Working topic",
            defaultOriginUrl,
            100,
            sourceReward
        );

        vm.prank(TestAddress.owner);
        rewardToken.approve(address(sourceAsserter), sourceReward);

        uint256 minimumBond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );
        defaultCurrency.allocateTo(TestAddress.account1, minimumBond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), minimumBond);

        vm.prank(TestAddress.account1);
        bytes32 assertionId = sourceAsserter.assertSource(
            topicId,
            labelString,
            url_,
            sourceDesc
        );

        assertEq(
            defaultCurrency.balanceOf(address(optimisticOracleV3)),
            minimumBond
        );

        timer.setCurrentTime(
            timer.getCurrentTime() + sourceAsserter.assertionLiveness() + 1
        );

        vm.expectCall(
            address(sourceAsserter),
            abi.encodeCall(
                sourceAsserter.assertionResolvedCallback,
                (assertionId, true)
            )
        );

        bool result = optimisticOracleV3.settleAndGetAssertionResult(
            assertionId
        );
        assertTrue(result);

        SourceAsserter.Source memory s = sourceAsserter.getSource(assertionId);
        assertEq(uint256(s.status), uint256(SourceAsserter.Status.Valid));
        assertEq(s.asserter, TestAddress.account1);
        assertEq(s.topicId, topicId);
        assertEq(s.label, labelHash);
        assertEq(s.url, url_);
        assertEq(string(s.description), sourceDesc);

        assertEq(rewardToken.balanceOf(TestAddress.account1), sourceReward);
    }

    // 1) initializeTopic edge‐cases
    function test_InitializeTopicEmptyDescriptionReverts() public {
        vm.prank(TestAddress.owner);
        vm.expectRevert(EmptyDescription.selector);
        sourceAsserter.initializeTopic(
            defaultTitle,
            "",
            defaultOriginUrl,
            100,
            sourceReward
        );
    }

    function test_InitializeTopicDuplicateSameBlockReverts() public {
        vm.prank(TestAddress.owner);
        string memory titleForDuplicateTest = "Duplicate Title";
        string memory desc = "Duplicate";
        string
            memory originUrlForDuplicateTest = "https://example.com/duplicate";
        sourceAsserter.initializeTopic(
            titleForDuplicateTest,
            desc,
            originUrlForDuplicateTest,
            100,
            sourceReward
        );
        vm.prank(TestAddress.owner);
        vm.expectRevert(TopicAlreadyExists.selector);
        sourceAsserter.initializeTopic(
            titleForDuplicateTest,
            desc,
            originUrlForDuplicateTest,
            100,
            sourceReward
        );
    }

    function test_InitializeTopicHappyPath() public {
        vm.prank(TestAddress.owner);
        uint256 duration = 123;
        string memory happyTitle = "Happy Topic Title";
        string memory happyDescription = "Happy";
        string memory happyOriginUrl = "https://example.com/happy-source";
        bytes32 topicId = sourceAsserter.initializeTopic(
            happyTitle,
            happyDescription,
            happyOriginUrl,
            duration,
            sourceReward
        );
        SourceAsserter.Topic memory t = sourceAsserter.getTopic(topicId);
        assertEq(string(t.title), happyTitle);
        assertEq(string(t.description), happyDescription);
        assertEq(string(t.originUrl), happyOriginUrl);
        assertEq(t.startTime, block.timestamp);
        assertEq(t.endTime, block.timestamp + duration);
        assertEq(t.sourceAssertions.length, 0);
        assertEq(t.creator, TestAddress.owner);
        assertEq(t.sourceReward, sourceReward);
    }

    // 2) assertSource before resolution
    function test_AssertSourcePendingAndArrayUpdated() public {
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "Await",
            defaultOriginUrl,
            100,
            sourceReward
        );

        uint256 bond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );
        defaultCurrency.allocateTo(TestAddress.account1, bond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), bond);

        vm.prank(TestAddress.account1);
        bytes32 assertionId = sourceAsserter.assertSource(
            topicId,
            labelString,
            url_,
            sourceDesc
        );

        SourceAsserter.Source memory s = sourceAsserter.getSource(assertionId);
        assertEq(uint256(s.status), uint256(SourceAsserter.Status.Pending));

        SourceAsserter.Topic memory tp = sourceAsserter.getTopic(topicId);
        assertEq(tp.sourceAssertions.length, 1);
        assertEq(tp.sourceAssertions[0], assertionId);
    }

    // 3) LabelRegistry behavior
    function test_LabelRegistryAddThenAssert() public {
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "LabelTest",
            defaultOriginUrl,
            100,
            sourceReward
        );

        uint256 bond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );
        defaultCurrency.allocateTo(TestAddress.account1, bond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), bond);

        vm.prank(TestAddress.account1);
        vm.expectRevert(InvalidLabel.selector);
        sourceAsserter.assertSource(topicId, "newlbl", url_, sourceDesc);

        vm.prank(TestAddress.owner);
        sourceAsserter.addLabel("newlbl");

        vm.prank(TestAddress.account1);
        bytes32 id2 = sourceAsserter.assertSource(
            topicId,
            "newlbl",
            url_,
            sourceDesc
        );
        assertEq(
            sourceAsserter.getSource(id2).label,
            keccak256(abi.encodePacked("newlbl"))
        );
    }

    // 4) UMA false‐resolution path
    function test_UMAFalseResolution() public {
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "FalseTest",
            defaultOriginUrl,
            100,
            sourceReward
        );
        vm.prank(TestAddress.owner);
        rewardToken.approve(address(sourceAsserter), sourceReward);

        uint256 bond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );
        defaultCurrency.allocateTo(TestAddress.account1, bond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), bond);

        vm.prank(TestAddress.account1);
        bytes32 assertionId = sourceAsserter.assertSource(
            topicId,
            labelString,
            url_,
            sourceDesc
        );

        OracleRequest memory req = _disputeAndGetOracleRequest(
            assertionId,
            bond
        );

        timer.setCurrentTime(
            timer.getCurrentTime() + sourceAsserter.assertionLiveness() + 1
        );

        _mockOracleResolved(address(mockOracle), req, false);

        vm.expectCall(
            address(sourceAsserter),
            abi.encodeCall(
                sourceAsserter.assertionResolvedCallback,
                (assertionId, false)
            )
        );

        bool result = optimisticOracleV3.settleAndGetAssertionResult(
            assertionId
        );
        assertFalse(result);

        SourceAsserter.Source memory s = sourceAsserter.getSource(assertionId);
        assertEq(uint256(s.status), uint256(SourceAsserter.Status.Rejected));
        assertEq(rewardToken.balanceOf(TestAddress.account1), 0);
    }

    // 5) multiple assertions after false
    function test_MultipleAssertionsAfterFalse() public {
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "Multi",
            defaultOriginUrl,
            100,
            sourceReward
        );

        vm.prank(TestAddress.owner);
        rewardToken.approve(address(sourceAsserter), sourceReward);

        uint256 bond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );
        defaultCurrency.allocateTo(TestAddress.account1, bond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), bond);

        vm.prank(TestAddress.account1);
        bytes32 id1 = sourceAsserter.assertSource(
            topicId,
            labelString,
            url_,
            sourceDesc
        );

        timer.setCurrentTime(
            timer.getCurrentTime() + sourceAsserter.assertionLiveness() + 1
        );
        optimisticOracleV3.settleAndGetAssertionResult(id1);

        defaultCurrency.allocateTo(TestAddress.account1, bond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), bond);
        vm.prank(TestAddress.account1);
        bytes32 id2 = sourceAsserter.assertSource(
            topicId,
            labelString,
            url_,
            sourceDesc
        );

        SourceAsserter.Topic memory tp = sourceAsserter.getTopic(topicId);
        assertEq(tp.sourceAssertions.length, 2);
        assertEq(tp.sourceAssertions[1], id2);
        assertEq(
            uint256(sourceAsserter.getSource(id2).status),
            uint256(SourceAsserter.Status.Pending)
        );
    }

    // 6) Label removal prevents new asserts
    function test_LabelRemovalPreventsAssert() public {
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "LabelRm",
            defaultOriginUrl,
            100,
            sourceReward
        );

        vm.prank(TestAddress.owner);
        sourceAsserter.removeLabel(labelString);

        uint256 bond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );
        defaultCurrency.allocateTo(TestAddress.account1, bond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), bond);

        vm.prank(TestAddress.account1);
        vm.expectRevert(InvalidLabel.selector);
        sourceAsserter.assertSource(topicId, labelString, url_, sourceDesc);
    }

    function test_StatusPendingToValid() public {
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "T1",
            defaultOriginUrl,
            100,
            sourceReward
        );
        vm.prank(TestAddress.owner);
        rewardToken.approve(address(sourceAsserter), sourceReward);

        uint256 bond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );
        defaultCurrency.allocateTo(TestAddress.account1, bond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), bond);

        vm.prank(TestAddress.account1);
        bytes32 assertionId = sourceAsserter.assertSource(
            topicId,
            labelString,
            url_,
            sourceDesc
        );

        // initial status is Pending
        SourceAsserter.Source memory s0 = sourceAsserter.getSource(assertionId);
        assertEq(uint256(s0.status), uint256(SourceAsserter.Status.Pending));

        // advance UMA time and settle true
        timer.setCurrentTime(
            timer.getCurrentTime() + sourceAsserter.assertionLiveness() + 1
        );
        vm.expectCall(
            address(sourceAsserter),
            abi.encodeCall(
                sourceAsserter.assertionResolvedCallback,
                (assertionId, true)
            )
        );
        bool ok = optimisticOracleV3.settleAndGetAssertionResult(assertionId);
        assertTrue(ok);

        // now status is Valid
        SourceAsserter.Source memory s1 = sourceAsserter.getSource(assertionId);
        assertEq(uint256(s1.status), uint256(SourceAsserter.Status.Valid));
    }

    function test_StatusPendingToDisputed() public {
        // setup…
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "T2",
            defaultOriginUrl,
            100,
            sourceReward
        );
        vm.prank(TestAddress.owner);
        rewardToken.approve(address(sourceAsserter), sourceReward);
        uint256 bond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );
        defaultCurrency.allocateTo(TestAddress.account1, bond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), bond);
        vm.prank(TestAddress.account1);
        bytes32 assertionId = sourceAsserter.assertSource(
            topicId,
            labelString,
            url_,
            sourceDesc
        );

        // still pending
        assertEq(
            uint256(sourceAsserter.getSource(assertionId).status),
            uint256(SourceAsserter.Status.Pending)
        );

        // dispute via UMA harness
        OracleRequest memory req = _disputeAndGetOracleRequest(
            assertionId,
            bond
        );

        // **right after the dispute**, before settlement, status must be Disputed**
        assertEq(
            uint256(sourceAsserter.getSource(assertionId).status),
            uint256(SourceAsserter.Status.Disputed)
        );
    }

    // 2) Check that after settlement=false we end up Rejected
    function test_StatusDisputedToRejectedAfterSettleFalse() public {
        // same setup…
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            defaultTitle,
            "T2",
            defaultOriginUrl,
            100,
            sourceReward
        );
        vm.prank(TestAddress.owner);
        rewardToken.approve(address(sourceAsserter), sourceReward);
        uint256 bond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );
        defaultCurrency.allocateTo(TestAddress.account1, bond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), bond);
        vm.prank(TestAddress.account1);
        bytes32 assertionId = sourceAsserter.assertSource(
            topicId,
            labelString,
            url_,
            sourceDesc
        );

        // dispute + advance + mock false
        OracleRequest memory req = _disputeAndGetOracleRequest(
            assertionId,
            bond
        );
        timer.setCurrentTime(
            timer.getCurrentTime() + sourceAsserter.assertionLiveness() + 1
        );
        _mockOracleResolved(address(mockOracle), req, false);

        // expect the settlement callback(false)
        vm.expectCall(
            address(sourceAsserter),
            abi.encodeCall(
                sourceAsserter.assertionResolvedCallback,
                (assertionId, false)
            )
        );
        bool ok = optimisticOracleV3.settleAndGetAssertionResult(assertionId);
        assertFalse(ok);

        // **now** status should be Rejected
        assertEq(
            uint256(sourceAsserter.getSource(assertionId).status),
            uint256(SourceAsserter.Status.Rejected)
        );
    }

    function test_TwoAssertions_SameTopic_SeparateRewardApprovals() public {
        // 1. Initialize Topic by TestAddress.owner
        vm.prank(TestAddress.owner);
        bytes32 topicId = sourceAsserter.initializeTopic(
            "Multi-Assertion Topic",
            "Testing two assertions on one topic",
            defaultOriginUrl,
            200, // Longer duration to accommodate two assertions
            sourceReward // Reward amount per successful assertion
        );

        uint256 minimumBond = optimisticOracleV3.getMinimumBond(
            address(defaultCurrency)
        );

        // --- First Assertion by TestAddress.account1 ---
        // Topic creator (TestAddress.owner) approves reward for the first assertion
        vm.prank(TestAddress.owner);
        rewardToken.approve(address(sourceAsserter), sourceReward);

        // Asserter1 (TestAddress.account1) setup for bond
        defaultCurrency.allocateTo(TestAddress.account1, minimumBond);
        vm.prank(TestAddress.account1);
        defaultCurrency.approve(address(sourceAsserter), minimumBond);

        // Asserter1 makes the assertion
        vm.prank(TestAddress.account1);
        bytes32 assertionId1 = sourceAsserter.assertSource(
            topicId,
            labelString,
            "url1.com",
            "First source description"
        );

        // Settle first assertion
        timer.setCurrentTime(
            timer.getCurrentTime() + sourceAsserter.assertionLiveness() + 1
        );
        vm.expectCall(
            address(sourceAsserter),
            abi.encodeCall(
                sourceAsserter.assertionResolvedCallback,
                (assertionId1, true)
            )
        );
        bool result1 = optimisticOracleV3.settleAndGetAssertionResult(
            assertionId1
        );
        assertTrue(result1, "First assertion should settle truthfully");

        // Verify Asserter1 received reward
        assertEq(
            rewardToken.balanceOf(TestAddress.account1),
            sourceReward,
            "Asserter1 reward incorrect"
        );
        SourceAsserter.Source memory s1 = sourceAsserter.getSource(assertionId1);
        assertEq(uint256(s1.status), uint256(SourceAsserter.Status.Valid), "S1 status invalid");

        // --- Second Assertion by TestAddress.account2 ---
        // Topic creator (TestAddress.owner) approves reward for the SECOND assertion
        vm.prank(TestAddress.owner);
        rewardToken.approve(address(sourceAsserter), sourceReward); // Key: separate approval

        // Asserter2 (TestAddress.account2) setup for bond
        defaultCurrency.allocateTo(TestAddress.account2, minimumBond);
        vm.prank(TestAddress.account2);
        defaultCurrency.approve(address(sourceAsserter), minimumBond);

        // Asserter2 makes the assertion
        vm.prank(TestAddress.account2);
        bytes32 assertionId2 = sourceAsserter.assertSource(
            topicId,
            labelString,
            "url2.com",
            "Second source description"
        );

        // Settle second assertion
        // Note: Advance time relative to the *current* time, which has already moved forward.
        // The liveness for assertionId2 starts when it's asserted.
        timer.setCurrentTime(
            timer.getCurrentTime() + sourceAsserter.assertionLiveness() + 1
        );
        vm.expectCall(
            address(sourceAsserter),
            abi.encodeCall(
                sourceAsserter.assertionResolvedCallback,
                (assertionId2, true)
            )
        );
        bool result2 = optimisticOracleV3.settleAndGetAssertionResult(
            assertionId2
        );
        assertTrue(result2, "Second assertion should settle truthfully");

        // Verify Asserter2 received reward
        assertEq(
            rewardToken.balanceOf(TestAddress.account2),
            sourceReward,
            "Asserter2 reward incorrect"
        );
        SourceAsserter.Source memory s2 = sourceAsserter.getSource(assertionId2);
        assertEq(uint256(s2.status), uint256(SourceAsserter.Status.Valid), "S2 status invalid");

        // Verify topic contains both assertions
        SourceAsserter.Topic memory t = sourceAsserter.getTopic(topicId);
        assertEq(t.sourceAssertions.length, 2, "Topic should have two assertions");
        assertEq(t.sourceAssertions[0], assertionId1);
        assertEq(t.sourceAssertions[1], assertionId2);
    }
}
