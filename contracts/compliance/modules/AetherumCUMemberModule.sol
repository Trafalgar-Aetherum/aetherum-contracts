// SPDX-License-Identifier: GPL-3.0
//
// Aetherum — Crypto-Collateralized Lending Infrastructure for U.S. Credit Unions
// Copyright (C) 2026, Aetherum, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// -----------------------------------------------------------------------
// CLEAN-ROOM NOTICE
//
// This contract implements the IModule interface defined by the ERC-3643
// standard (GPL-3.0). It was written independently and shares no code
// with Tokeny's proprietary compliance modules (CC-BY-NC-4.0).
//
// The CU membership verification and DACS score integration are
// original Aetherum IP with no analog in the Tokeny module library.
// -----------------------------------------------------------------------

pragma solidity 0.8.17;

import "@tokenysolutions/t-rex/contracts/compliance/modular/IModularCompliance.sol";
import "@tokenysolutions/t-rex/contracts/token/IToken.sol";
import "@tokenysolutions/t-rex/contracts/compliance/modular/modules/AbstractModuleUpgradeable.sol";

/**
 * @title AetherumCUMemberModule
 * @notice Verifies that a borrower is an active member of the credit union
 *         administering this compliance contract, and that their DACS score
 *         meets the minimum threshold set by that credit union.
 *
 * @dev This is Aetherum's most differentiated compliance module — it has no
 *      equivalent in Tokeny's library because it's purpose-built for the
 *      credit union lending use case.
 *
 *      Architecture:
 *        - Each credit union runs its own compliance contract (one per CU).
 *        - The CU's agent registers approved member wallet addresses via
 *          registerMember() with their current DACS score.
 *        - The CU sets its minimum acceptable DACS score threshold.
 *        - On every transfer, this module checks:
 *            (a) Is the receiver a registered member of this CU?
 *            (b) Does their DACS score meet the minimum threshold?
 *        - The CU's agent can update a member's score (e.g. after monthly
 *          DACS refresh) or revoke membership (e.g. account closure).
 *
 *      DACS Score:
 *        Aetherum's proprietary Digital Asset Credit Score (risk assessment
 *        model, patent-pending #63/897,067). Scores range 300–850, same
 *        scale as FICO for familiarity. The minimum threshold is set per CU.
 *        Default minimum: 620.
 *
 *      Implements the ERC-3643 IModule interface (GPL-3.0).
 *      Written independently — no Tokeny CC-BY-NC-4.0 code used.
 */
contract AetherumCUMemberModule is AbstractModuleUpgradeable {

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    /// @notice Minimum possible DACS score.
    uint16 public constant DACS_MIN = 300;

    /// @notice Maximum possible DACS score.
    uint16 public constant DACS_MAX = 850;

    /// @notice Default minimum DACS score threshold (configurable per CU).
    uint16 public constant DEFAULT_MIN_DACS = 620;

    // -----------------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------------

    /// @dev Member registry per compliance contract.
    ///      compliance address → member wallet → MemberRecord
    struct MemberRecord {
        bool active;        // Is this an active CU member?
        uint16 dacsScore;   // Most recent DACS score (300-850)
        uint32 updatedAt;   // Timestamp of last score update
    }

    mapping(address => mapping(address => MemberRecord)) private _members;

    /// @dev Minimum DACS score per compliance contract (CU-configurable).
    mapping(address => uint16) private _minDacsScore;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /**
     * @notice Emitted when a member is registered or their record is updated.
     * @param compliance  The compliance contract (one per CU).
     * @param member      The member's wallet address.
     * @param dacsScore   Their DACS score at time of registration/update.
     */
    event MemberRegistered(
        address indexed compliance,
        address indexed member,
        uint16 dacsScore
    );

    /**
     * @notice Emitted when a member's DACS score is updated.
     * @param compliance  The compliance contract.
     * @param member      The member's wallet address.
     * @param oldScore    Their previous DACS score.
     * @param newScore    Their new DACS score.
     */
    event DACSSoreUpdated(
        address indexed compliance,
        address indexed member,
        uint16 oldScore,
        uint16 newScore
    );

    /**
     * @notice Emitted when a member is deactivated.
     * @param compliance  The compliance contract.
     * @param member      The member's wallet address.
     */
    event MemberDeactivated(address indexed compliance, address indexed member);

    /**
     * @notice Emitted when a CU updates its minimum DACS score threshold.
     * @param compliance   The compliance contract.
     * @param minDacsScore The new minimum threshold.
     */
    event MinDACSSoreUpdated(address indexed compliance, uint16 minDacsScore);

    // -----------------------------------------------------------------------
    // Custom Errors
    // -----------------------------------------------------------------------

    /// @notice Thrown when a DACS score is outside the valid 300-850 range.
    error InvalidDACSSore(uint16 score);

    /// @notice Thrown when an address is not a registered member of this CU.
    error NotCUMember(address wallet);

    /// @notice Thrown when a member's DACS score is below the CU's threshold.
    error DACSSoreBelowThreshold(address member, uint16 score, uint16 minimum);

    // -----------------------------------------------------------------------
    // Initializer
    // -----------------------------------------------------------------------

    /**
     * @notice Initializes the upgradeable module.
     * @dev Must be called exactly once at deployment via a proxy.
     */
    function initialize() external initializer {
        __AbstractModule_init();
    }

    // -----------------------------------------------------------------------
    // Member Management (called by compliance contract = CU agent)
    // -----------------------------------------------------------------------

    /**
     * @notice Registers a CU member and sets their initial DACS score.
     * @dev Only callable by the bound compliance contract (CU agent role).
     *      CU agents call this during member onboarding after Aetherum
     *      completes initial DACS scoring.
     * @param _member    The member's wallet address.
     * @param _dacsScore Their initial DACS score (300-850).
     */
    function registerMember(
        address _member,
        uint16 _dacsScore
    ) external onlyComplianceCall {
        if (_dacsScore < DACS_MIN || _dacsScore > DACS_MAX) {
            revert InvalidDACSSore(_dacsScore);
        }
        _members[msg.sender][_member] = MemberRecord({
            active: true,
            dacsScore: _dacsScore,
            updatedAt: uint32(block.timestamp)
        });
        emit MemberRegistered(msg.sender, _member, _dacsScore);
    }

    /**
     * @notice Batch registers multiple members in a single transaction.
     * @dev Gas-optimized for CU onboarding flows. Arrays must be same length.
     * @param _memberWallets  Array of member wallet addresses.
     * @param _dacsScores     Array of corresponding DACS scores.
     */
    function batchRegisterMembers(
        address[] calldata _memberWallets,
        uint16[] calldata _dacsScores
    ) external onlyComplianceCall {
        require(_memberWallets.length == _dacsScores.length, "array length mismatch");
        for (uint256 i = 0; i < _memberWallets.length; i++) {
            if (_dacsScores[i] < DACS_MIN || _dacsScores[i] > DACS_MAX) {
                revert InvalidDACSSore(_dacsScores[i]);
            }
            _members[msg.sender][_memberWallets[i]] = MemberRecord({
                active: true,
                dacsScore: _dacsScores[i],
                updatedAt: uint32(block.timestamp)
            });
            emit MemberRegistered(msg.sender, _memberWallets[i], _dacsScores[i]);
        }
    }

    /**
     * @notice Updates a member's DACS score after a refresh cycle.
     * @dev Called by the CU agent after Aetherum's monthly DACS recalculation.
     *      If the score drops below the CU's threshold, the member's existing
     *      collateral position is not immediately liquidated — but they cannot
     *      receive additional collateral tokens until their score recovers.
     * @param _member    The member's wallet address.
     * @param _newScore  Their updated DACS score (300-850).
     */
    function updateDACSSore(
        address _member,
        uint16 _newScore
    ) external onlyComplianceCall {
        if (_newScore < DACS_MIN || _newScore > DACS_MAX) {
            revert InvalidDACSSore(_newScore);
        }
        MemberRecord storage record = _members[msg.sender][_member];
        uint16 oldScore = record.dacsScore;
        record.dacsScore = _newScore;
        record.updatedAt = uint32(block.timestamp);
        emit DACSSoreUpdated(msg.sender, _member, oldScore, _newScore);
    }

    /**
     * @notice Deactivates a CU member (account closure, fraud, etc).
     * @dev Deactivated members cannot receive collateral tokens.
     *      Existing positions remain on-chain (for liquidation if needed).
     *      The CU agent must handle position resolution separately.
     * @param _member The member's wallet address.
     */
    function deactivateMember(address _member) external onlyComplianceCall {
        _members[msg.sender][_member].active = false;
        emit MemberDeactivated(msg.sender, _member);
    }

    /**
     * @notice Sets the minimum DACS score threshold for this CU.
     * @dev Default is DEFAULT_MIN_DACS (620) if not explicitly set.
     *      CUs may tighten (raise) or loosen (lower) this independently.
     * @param _minDacs Minimum acceptable DACS score (300-850).
     */
    function setMinDACSSore(uint16 _minDacs) external onlyComplianceCall {
        if (_minDacs < DACS_MIN || _minDacs > DACS_MAX) {
            revert InvalidDACSSore(_minDacs);
        }
        _minDacsScore[msg.sender] = _minDacs;
        emit MinDACSSoreUpdated(msg.sender, _minDacs);
    }

    // -----------------------------------------------------------------------
    // IModule — Transfer / Mint / Burn Actions
    // -----------------------------------------------------------------------

    /**
     * @notice No state update required on transfer for this module.
     * @dev Membership and DACS are checked per-transfer via moduleCheck.
     *      The member registry is updated externally by the CU agent.
     */
    function moduleTransferAction(
        address /*_from*/,
        address /*_to*/,
        uint256 /*_value*/
    ) external override onlyComplianceCall {}

    /**
     * @notice No state update required on mint.
     */
    function moduleMintAction(
        address /*_to*/,
        uint256 /*_value*/
    ) external override onlyComplianceCall {}

    /**
     * @notice No state update required on burn.
     */
    function moduleBurnAction(
        address /*_from*/,
        uint256 /*_value*/
    ) external override onlyComplianceCall {}

    // -----------------------------------------------------------------------
    // IModule — Compliance Check
    // -----------------------------------------------------------------------

    /**
     * @notice Returns true only if the receiver is:
     *           (a) an active registered member of this CU, AND
     *           (b) has a DACS score at or above the CU's minimum threshold.
     *
     * @dev This check is the core Aetherum IP — the intersection of
     *      traditional credit union membership verification and on-chain
     *      crypto-collateral risk assessment via DACS.
     *
     * @param _from       Sender (not checked — only receiver eligibility matters).
     * @param _to         Receiver whose membership and DACS we verify.
     * @param _value      Transfer amount (unused in this module).
     * @param _compliance The compliance contract (identifies which CU).
     * @return bool       True if receiver passes both membership and DACS checks.
     */
    function moduleCheck(
        address _from,
        address _to,
        uint256 _value,
        address _compliance
    ) external view override returns (bool) {
        (_from, _value);

        MemberRecord memory record = _members[_compliance][_to];

        // Check (a): Must be an active CU member
        if (!record.active) {
            return false;
        }

        // Check (b): DACS score must meet or exceed CU's minimum threshold
        uint16 minDacs = _getMinDACS(_compliance);
        if (record.dacsScore < minDacs) {
            return false;
        }

        return true;
    }

    // -----------------------------------------------------------------------
    // IModule — Metadata
    // -----------------------------------------------------------------------

    /**
     * @notice Not plug-and-play — requires member registration before use.
     * @dev Returns false so compliance system enforces preset before binding.
     */
    function isPlugAndPlay() external pure override returns (bool) {
        return false;
    }

    /**
     * @notice Any compliance contract may bind to this module.
     */
    function canComplianceBind(
        address /*_compliance*/
    ) external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Returns the human-readable name of this module.
     */
    function name() external pure override returns (string memory) {
        return "AetherumCUMemberModule";
    }

    // -----------------------------------------------------------------------
    // Public Getters
    // -----------------------------------------------------------------------

    /**
     * @notice Returns the full membership record for a wallet.
     * @param _compliance The compliance contract address.
     * @param _member     The member's wallet address.
     * @return active     Whether the member is currently active.
     * @return dacsScore  Their most recent DACS score.
     * @return updatedAt  Timestamp of their last score update.
     */
    function getMemberRecord(
        address _compliance,
        address _member
    ) external view returns (bool active, uint16 dacsScore, uint32 updatedAt) {
        MemberRecord memory record = _members[_compliance][_member];
        return (record.active, record.dacsScore, record.updatedAt);
    }

    /**
     * @notice Returns the minimum DACS score configured for this CU.
     * @param _compliance The compliance contract address.
     * @return uint16     Minimum DACS score (default 620).
     */
    function getMinDACSSore(address _compliance) external view returns (uint16) {
        return _getMinDACS(_compliance);
    }

    /**
     * @notice Convenience check — returns true if a member is eligible
     *         (active + DACS above threshold).
     * @param _compliance The compliance contract address.
     * @param _member     The member's wallet address.
     * @return bool       True if eligible to receive collateral tokens.
     */
    function isMemberEligible(
        address _compliance,
        address _member
    ) external view returns (bool) {
        MemberRecord memory record = _members[_compliance][_member];
        if (!record.active) return false;
        return record.dacsScore >= _getMinDACS(_compliance);
    }

    // -----------------------------------------------------------------------
    // Internal Helpers
    // -----------------------------------------------------------------------

    /**
     * @dev Returns the configured minimum DACS score for a compliance contract,
     *      falling back to DEFAULT_MIN_DACS if not explicitly set.
     */
    function _getMinDACS(address _compliance) internal view returns (uint16) {
        uint16 configured = _minDacsScore[_compliance];
        return configured == 0 ? DEFAULT_MIN_DACS : configured;
    }
}
