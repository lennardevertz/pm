// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibString} from "./utils/LibString.sol";

import {OnitInfiniteOutcomeDPMMechanism} from "./mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMMechanism.sol";
import {OnitMarketResolver} from "./resolvers/OnitMarketResolver.sol";

/**
 * @title Onit Infinite Outcome Dynamic Parimutual Market
 *
 * @author Onit Labs (https://github.com/onit-labs)
 *
 * @notice Decentralized prediction market for continuous outcomes
 *
 * @dev Notes on the market:
 * - See OnitInfiniteOutcomeDPMMechanism for explanation of the mechanism
 * - See OnitInfiniteOutcomeDPMOutcomeDomain for explanation of the outcome domain and token tracking
 */
contract OnitInfiniteOutcomeDPM is
    OnitInfiniteOutcomeDPMMechanism,
    OnitMarketResolver
{
    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    /// Configuration Errors
    error AlreadyInitialized();
    error BettingCutoffOutOfBounds();
    error UnauthorizedCaller(); // New error for access control
    /// Trading Errors
    error BettingCutoffPassed();
    error UserAlreadySubmitted(); // New error for preventing resubmissions
    error NegativeSharesNotAllowed(); // New error for ensuring positive shares on initial submission
    error InvalidSharesValue();
    error WithdrawalDelayPeriodNotPassed();

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    /// Market Lifecycle Events
    event MarketInitialized(address indexed initiator, uint256 initialBacking);
    event BettingCutoffUpdated(uint256 bettingCutoff);
    /// Trading Events
    event BoughtShares(
        address indexed predictor,
        int256 costDiff,
        int256 newTotalQSquared
    );

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    mapping(address => bool) public hasUserSubmitted;
    /// Timestamp after which no more bets can be placed (0 = no cutoff)
    uint256 public bettingCutoff;
    /// Number of shares at the resolved outcome
    int256 public winningBucketSharesAtClose;

    address public authorizedSubmitter; // Address authorized to submit confidence (e.g., Voting contract)
    /// The name of the market
    string public name = "Onit Prediction Market";
    /// The symbol of the market
    string public symbol = "ONIT";
    /// The question traders are predicting
    string public marketQuestion;
    /// The version of the market
    string public constant VERSION = "0.0.3";

    /// Market configuration params passed to initialize the market
    struct MarketConfig {
        uint256 bettingCutoff;
        uint256 withdrawlDelayPeriod;
        int256 outcomeUnit;
        string marketQuestion;
        string marketUri;
        address[] resolvers;
    }

    /// Market initialization data
    struct MarketInitData {
        /// Onit factory contract with the Onit admin address
        address onitFactory;
        /// Address authorized to submit confidence shares (e.g., Voting contract)
        address authorizedSubmitterAddress;
        /// Address that gets the initial prediction
        address initiator;
        /// Market configuration
        MarketConfig config;
        /// Bucket ids for the initial prediction
        int256[] initialBucketIds;
        /// Shares for the initial prediction
        int256[] initialShares;
        /// Kappa value for the DPM
        int256 initKappa;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @notice Construct the implementation of the market
     *
     * @dev Initialize owner to a dummy address to prevent implementation from being initialized
     */
    constructor() {
        // Used as flag to prevent implementation from being initialized, and to prevent bets
        marketVoided = true;
    }

    /**
     * @notice Initialize the market contract
     *
     * @dev This function can only be called once when the proxy is first deployed
     *
     * @param initData The market initialization data
     */
    function initialize(MarketInitData memory initData) external {
        // Not payable
        // Prevents the implementation from being initialized
        if (marketVoided) revert AlreadyInitialized();
        // If cutoff is set, it must be greater than now
        if (
            initData.config.bettingCutoff != 0 &&
            initData.config.bettingCutoff <= block.timestamp
        ) {
            revert BettingCutoffOutOfBounds();
        }
        // Initialize Onit admin and resolvers
        _initializeOnitMarketResolver(
            initData.config.withdrawlDelayPeriod,
            initData.onitFactory,
            initData.config.resolvers
        );

        // Initialize Infinite Outcome DPM
        _initializeInfiniteOutcomeDPM(
            initData.initiator,
            initData.config.outcomeUnit,
            initData.initialShares,
            initData.initialBucketIds,
            initData.initKappa // Pass kappa from initData
        );

        // Set market description
        marketQuestion = initData.config.marketQuestion;
        // Set time limit for betting
        bettingCutoff = initData.config.bettingCutoff;
        // Set authorized submitter
        authorizedSubmitter = initData.authorizedSubmitterAddress;
        if (authorizedSubmitter == address(0)) revert UnauthorizedCaller();

        // Emit with 0 as initial backing since DPM doesn't hold funds
        emit MarketInitialized(initData.initiator, 0);
    }

    // ----------------------------------------------------------------
    // Admin functions
    // ----------------------------------------------------------------

    /**
     * @notice Set the resolved outcome, closing the market
     *
     * @param _resolvedOutcome The resolved value of the market
     */
    function resolveMarket(int256 _resolvedOutcome) external onlyResolver {
        _setResolvedOutcome(_resolvedOutcome, getBucketId(_resolvedOutcome));
        // Fee and totalPayout calculations removed

        winningBucketSharesAtClose = getBucketOutstandingShares(
            resolvedBucketId
        );

        emit MarketResolved(_resolvedOutcome, winningBucketSharesAtClose, 0);
    }

    /**
     * @notice Update the resolved outcome
     *
     * @param _resolvedOutcome The new resolved outcome
     *
     * @dev This is used to update the resolved outcome after the market has been resolved
     *      It is designed to real with disputes about the outcome.
     *      Can only be called:
     *      - By the owner
     *      - If the market is resolved
     *      - If the withdrawl delay period is open
     */
    function updateResolution(
        int256 _resolvedOutcome
    ) external onlyOnitFactoryOwner {
        _updateResolvedOutcome(_resolvedOutcome, getBucketId(_resolvedOutcome));
    }

    /**
     * @notice Update the betting cutoff
     *
     * @param _bettingCutoff The new betting cutoff
     *
     * @dev Can only be called by the Onit factory owner
     * @dev This enables the owner to extend the betting period, or close betting early without resolving the market
     * - It allows for handling unexpected events that delay the market resolution criteria being confirmed
     * - This function should be made more robust in future versions
     */
    function updateBettingCutoff(
        uint256 _bettingCutoff
    ) external onlyOnitFactoryOwner {
        bettingCutoff = _bettingCutoff;

        emit BettingCutoffUpdated(_bettingCutoff);
    }

    /**
     * @notice Sets the authorized submitter address (e.g., the Voting contract).
     * @param _newSubmitter The address of the new authorized submitter.
     */
    function setAuthorizedSubmitter(
        address _newSubmitter
    ) external onlyOnitFactoryOwner {
        if (_newSubmitter == address(0)) revert UnauthorizedCaller(); // Cannot be address(0)
        authorizedSubmitter = _newSubmitter;
    }

    // ----------------------------------------------------------------
    // Public market functions
    // ----------------------------------------------------------------

    /**
     * @notice Submits confidence shares on behalf of a user.
     * @dev Only callable by the `authorizedSubmitter` (e.g., Voting contract).
     *      Shares are pre-weighted by the `Voting` contract based on user's stake.
     * @param user The end-user for whom the shares are being submitted.
     * @param bucketIds The bucket IDs for the user's confidence distribution.
     * @param shares The pre-weighted shares for the user's confidence distribution.
     */
    function submitConfidenceShares(
        address user,
        int256[] memory bucketIds,
        int256[] memory shares
    ) external {
        if (msg.sender != authorizedSubmitter) revert UnauthorizedCaller();
        if (hasUserSubmitted[user]) revert UserAlreadySubmitted();
        for (uint256 i = 0; i < shares.length; i++) {
            if (shares[i] < 0) revert NegativeSharesNotAllowed();
        }
        if (bettingCutoff != 0 && block.timestamp > bettingCutoff)
            revert BettingCutoffPassed();
        if (resolvedAtTimestamp != 0) revert MarketIsResolved();
        if (marketVoided) revert MarketIsVoided();

        // Calculate new totalQSquared based on the share changes.
        // The `costDiff` from `calculateCostOfTrade` is not used for payment here.
        (int256 costDiff, int256 newTotalQSquared) = calculateCostOfTrade(
            bucketIds,
            shares
        );

        // Track the latest totalQSquared so we don't need to recalculate it
        totalQSquared = newTotalQSquared;
        // Update the markets outcome token holdings
        _updateHoldings(user, bucketIds, shares); // Pass `user` not `msg.sender`

        hasUserSubmitted[user] = true; // Mark user as having submitted

        emit BoughtShares(user, costDiff, newTotalQSquared);
    }
}
