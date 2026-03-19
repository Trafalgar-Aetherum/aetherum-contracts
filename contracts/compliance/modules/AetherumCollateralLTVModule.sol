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
// The LTV logic and collateral model are original Aetherum IP.
// -----------------------------------------------------------------------

pragma solidity 0.8.17;

import "@tokenysolutions/t-rex/contracts/compliance/modular/IModularCompliance.sol";
import "@tokenysolutions/t-rex/contracts/token/IToken.sol";
import "@tokenysolutions/t-rex/contracts/compliance/modular/modules/AbstractModuleUpgradeable.sol";

/**
 * @title AetherumCollateralLTVModule
 * @notice Enforces per-borrower maximum Loan-to-Value (LTV) ratios on
 *         crypto-collateral token positions held by credit union members.
 *
 * @dev In Aetherum's lending model, a borrower's collateral is represented
 *      as ERC-3643 tokens locked in a position. This module ensures that
 *      no single borrower can hold more collateral tokens than their
 *      credit union's configured maximum LTV threshold allows.
 *
 *      Each compliance contract (one per CU) sets its own maxCollateralBps
 *      (basis points of total supply). This lets CUs configure conservative
 *      or aggressive LTV policies independently.
 *
 *      LTV enforcement model:
 *        - maxCollateralBps = 7000 → a single borrower cannot hold
 *          more than 70% of the total collateral token supply.
 *        - Default is 7000 bps (70% LTV), configurable per CU.
 *
 *      This module tracks per-borrower balances and checks proposed
 *      transfers against the configured ceiling before allowing them.
 *
 *      Implements the ERC-3643 IModule interface (GPL-3.0).
 *      Written independently — no Tokeny CC-BY-NC-4.0 code used.
 */
contract AetherumCollateralLTVModule is AbstractModuleUpgradeable {

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    /// @notice Basis points denominator (10000 = 100%).
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Default maximum LTV in basis points: 70%.
    uint16 public constant DEFAULT_MAX_LTV_BPS = 7_000;

    /// @notice Absolute maximum LTV allowed: 80% (hard cap, non-configurable).
    uint16 public constant HARD_CAP_LTV_BPS = 8_000;

    // -----------------------------------------------------------------------
    // Storage
    // -----------------------------------------------------------------------

    /// @dev Per-compliance max LTV in basis points.
    ///      compliance address → maxLtvBps
    mapping(address => uint16) private _maxLtvBps;

    /// @dev Per-compliance, per-borrower collateral token balance tracked
    ///      by this module (mirrors on-chain balance but maintained separately
    ///      to avoid re-entrancy via live balance queries during transfer checks).
    ///      compliance address → borrower address → tracked balance
    mapping(address => mapping(address => uint256)) private _collateralBalance;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /**
     * @notice Emitted when a CU updates its maximum LTV configuration.
     * @param compliance  The compliance contract (one per CU).
     * @param maxLtvBps   The new maximum LTV in basis points.
     */
    event MaxLTVUpdated(address indexed compliance, uint16 maxLtvBps);

    /**
     * @notice Emitted when a transfer is rejected due to LTV breach.
     * @param compliance       The compliance contract.
     * @param receiver         The borrower who would exceed LTV.
     * @param currentBalance   Their current collateral balance.
     * @param attemptedAmount  The additional amount attempted.
     * @param maxAllowed       The maximum they are permitted to hold.
     */
    event LTVCheckFailed(
        address indexed compliance,
        address indexed receiver,
        uint256 currentBalance,
        uint256 attemptedAmount,
        uint256 maxAllowed
    );

    // -----------------------------------------------------------------------
    // Custom Errors
    // -----------------------------------------------------------------------

    /// @notice Thrown when the proposed LTV exceeds the hard cap.
    error LTVExceedsHardCap(uint16 proposed, uint16 hardCap);

    /// @notice Thrown when a transfer would push a borrower over their LTV ceiling.
    error LTVBreached(address receiver, uint256 newBalance, uint256 maxAllowed);

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
    // Configuration (called by compliance contract = CU agent)
    // -----------------------------------------------------------------------

    /**
     * @notice Sets the maximum LTV for the calling compliance contract (CU).
     * @dev Can only be called by a bound compliance contract.
     *      Cannot exceed HARD_CAP_LTV_BPS (80%).
     * @param maxLtvBps_ Maximum LTV in basis points (e.g. 7000 = 70%).
     */
    function setMaxLTV(uint16 maxLtvBps_) external onlyComplianceCall {
        if (maxLtvBps_ > HARD_CAP_LTV_BPS) {
            revert LTVExceedsHardCap(maxLtvBps_, HARD_CAP_LTV_BPS);
        }
        _maxLtvBps[msg.sender] = maxLtvBps_;
        emit MaxLTVUpdated(msg.sender, maxLtvBps_);
    }

    // -----------------------------------------------------------------------
    // IModule — Transfer / Mint / Burn Actions
    // -----------------------------------------------------------------------

    /**
     * @notice Updates tracked collateral balances on transfer.
     * @dev Called by the compliance contract after a successful transfer.
     *      Decrements sender's tracked balance, increments receiver's.
     */
    function moduleTransferAction(
        address _from,
        address _to,
        uint256 _value
    ) external override onlyComplianceCall {
        // Decrement sender (can't underflow — transfer already validated)
        if (_from != address(0)) {
            _collateralBalance[msg.sender][_from] -= _value;
        }
        // Increment receiver
        _collateralBalance[msg.sender][_to] += _value;
    }

    /**
     * @notice Updates tracked balance on mint.
     * @dev Minting represents new collateral being locked for a loan.
     */
    function moduleMintAction(
        address _to,
        uint256 _value
    ) external override onlyComplianceCall {
        _collateralBalance[msg.sender][_to] += _value;
    }

    /**
     * @notice Updates tracked balance on burn.
     * @dev Burning represents collateral being released (loan repaid or liquidated).
     */
    function moduleBurnAction(
        address _from,
        uint256 _value
    ) external override onlyComplianceCall {
        _collateralBalance[msg.sender][_from] -= _value;
    }

    // -----------------------------------------------------------------------
    // IModule — Compliance Check
    // -----------------------------------------------------------------------

    /**
     * @notice Returns true only if the transfer would not push the receiver
     *         above their maximum permitted collateral balance (LTV ceiling).
     *
     * @dev The maximum a single borrower can hold is:
     *        maxAllowed = (totalSupply * maxLtvBps) / BPS_DENOMINATOR
     *
     *      We check: currentBalance + _value <= maxAllowed
     *
     *      Uses tracked internal balances rather than live token.balanceOf()
     *      to avoid re-entrancy and to keep the check gas-efficient.
     *
     * @param _from       Sender (not used in LTV check).
     * @param _to         Receiver whose collateral position we check.
     * @param _value      Amount of collateral tokens being transferred.
     * @param _compliance The compliance contract (identifies which CU).
     * @return bool       True if transfer is within LTV limits.
     */
    function moduleCheck(
        address _from,
        address _to,
        uint256 _value,
        address _compliance
    ) external view override returns (bool) {
        (_from);

        uint16 maxLtv = _getMaxLTV(_compliance);
        uint256 totalSupply = IToken(
            IModularCompliance(_compliance).getTokenBound()
        ).totalSupply();

        // If supply is zero (initial state), allow minting
        if (totalSupply == 0) return true;

        uint256 maxAllowed = (totalSupply * maxLtv) / BPS_DENOMINATOR;
        uint256 currentBalance = _collateralBalance[_compliance][_to];
        uint256 newBalance = currentBalance + _value;

        return newBalance <= maxAllowed;
    }

    // -----------------------------------------------------------------------
    // IModule — Metadata
    // -----------------------------------------------------------------------

    /**
     * @notice Not plug-and-play — requires setMaxLTV() configuration by CU agent.
     * @dev Returns false so the compliance system enforces preset configuration.
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
        return "AetherumCollateralLTVModule";
    }

    // -----------------------------------------------------------------------
    // Public Getters
    // -----------------------------------------------------------------------

    /**
     * @notice Returns the maximum LTV configured for a given compliance contract.
     * @param _compliance The compliance contract address (one per CU).
     * @return uint16     Max LTV in basis points (default 7000 = 70%).
     */
    function getMaxLTV(address _compliance) external view returns (uint16) {
        return _getMaxLTV(_compliance);
    }

    /**
     * @notice Returns the tracked collateral balance for a borrower.
     * @param _compliance  The compliance contract address.
     * @param _borrower    The borrower's wallet address.
     * @return uint256     Tracked collateral token balance.
     */
    function getCollateralBalance(
        address _compliance,
        address _borrower
    ) external view returns (uint256) {
        return _collateralBalance[_compliance][_borrower];
    }

    /**
     * @notice Returns the maximum collateral a borrower can hold under
     *         the current LTV config and total supply.
     * @param _compliance  The compliance contract address.
     * @param _totalSupply Current total supply of the collateral token.
     * @return uint256     Maximum tokens a single borrower may hold.
     */
    function getMaxCollateralAllowed(
        address _compliance,
        uint256 _totalSupply
    ) external view returns (uint256) {
        uint16 maxLtv = _getMaxLTV(_compliance);
        return (_totalSupply * maxLtv) / BPS_DENOMINATOR;
    }

    // -----------------------------------------------------------------------
    // Internal Helpers
    // -----------------------------------------------------------------------

    /**
     * @dev Returns the configured max LTV for a compliance contract,
     *      falling back to DEFAULT_MAX_LTV_BPS if not explicitly set.
     */
    function _getMaxLTV(address _compliance) internal view returns (uint16) {
        uint16 configured = _maxLtvBps[_compliance];
        return configured == 0 ? DEFAULT_MAX_LTV_BPS : configured;
    }
}
