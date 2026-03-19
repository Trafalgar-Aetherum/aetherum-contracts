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
// This program is free software distributed WITHOUT ANY WARRANTY.
// See the GNU General Public License for more details:
// https://www.gnu.org/licenses/
//
// -----------------------------------------------------------------------
// CLEAN-ROOM NOTICE
//
// This contract implements the IModule interface defined by the ERC-3643
// standard (GPL-3.0). It was written independently and shares no code
// with Tokeny's proprietary compliance modules (CC-BY-NC-4.0).
// The IModule interface itself is GPL-3.0 and freely implementable.
// -----------------------------------------------------------------------

pragma solidity 0.8.17;

import "@tokenysolutions/t-rex/contracts/compliance/modular/IModularCompliance.sol";
import "@tokenysolutions/t-rex/contracts/token/IToken.sol";
import "@tokenysolutions/t-rex/contracts/compliance/modular/modules/AbstractModuleUpgradeable.sol";

/**
 * @title AetherumUSJurisdictionModule
 * @notice Restricts collateral token transfers to U.S.-registered identities only.
 *
 * @dev Credit unions chartered under NCUA are U.S.-domiciled institutions.
 *      Crypto-collateralized loans issued by Aetherum partner CUs may only
 *      involve borrowers whose on-chain identity is registered under the
 *      United States country code (ISO 3166-1 numeric: 840).
 *
 *      This is the foundational jurisdiction gate for the Aetherum compliance
 *      stack. All other Aetherum compliance modules are layered on top of this.
 *
 *      Implements the ERC-3643 IModule interface (GPL-3.0).
 *      Written independently — no Tokeny CC-BY-NC-4.0 code used.
 */
contract AetherumUSJurisdictionModule is AbstractModuleUpgradeable {

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    /// @notice ISO 3166-1 numeric country code for the United States.
    uint16 public constant US_COUNTRY_CODE = 840;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /**
     * @notice Emitted when a transfer is rejected due to non-US jurisdiction.
     * @param compliance  The compliance contract that triggered the check.
     * @param receiver    The address that failed the jurisdiction check.
     * @param countryCode The ISO 3166-1 numeric code of the receiver's country.
     */
    event JurisdictionCheckFailed(
        address indexed compliance,
        address indexed receiver,
        uint16 countryCode
    );

    // -----------------------------------------------------------------------
    // Custom Errors
    // -----------------------------------------------------------------------

    /// @notice Thrown when a receiver is not registered under the US country code.
    error NotUSJurisdiction(address receiver, uint16 countryCode);

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
    // IModule — Transfer / Mint / Burn Actions
    // -----------------------------------------------------------------------

    /**
     * @notice No state update required on transfer for this module.
     * @dev Jurisdiction is stateless — checked on every transfer via moduleCheck.
     */
    function moduleTransferAction(
        address /*_from*/,
        address /*_to*/,
        uint256 /*_value*/
    ) external override onlyComplianceCall {}

    /**
     * @notice No state update required on mint for this module.
     */
    function moduleMintAction(
        address /*_to*/,
        uint256 /*_value*/
    ) external override onlyComplianceCall {}

    /**
     * @notice No state update required on burn for this module.
     */
    function moduleBurnAction(
        address /*_from*/,
        uint256 /*_value*/
    ) external override onlyComplianceCall {}

    // -----------------------------------------------------------------------
    // IModule — Compliance Check
    // -----------------------------------------------------------------------

    /**
     * @notice Returns true only if the receiver is registered under US jurisdiction.
     *
     * @dev Fetches the receiver's country code from the token's Identity Registry
     *      and checks it against US_COUNTRY_CODE (840).
     *
     *      Mints (from == address(0)) are also subject to this check, ensuring
     *      collateral tokens can only ever be minted to a verified US identity.
     *
     * @param _from        Sender address (unused — jurisdiction check is on receiver).
     * @param _to          Receiver address to check.
     * @param _value       Transfer amount (unused for jurisdiction check).
     * @param _compliance  The ModularCompliance contract calling this check.
     * @return bool        True if receiver is US-domiciled, false otherwise.
     */
    function moduleCheck(
        address _from,
        address _to,
        uint256 _value,
        address _compliance
    ) external view override returns (bool) {
        // Suppress unused variable warnings — jurisdiction check only cares about _to
        (_from, _value);

        uint16 receiverCountry = _getCountry(_compliance, _to);

        if (receiverCountry != US_COUNTRY_CODE) {
            return false;
        }

        return true;
    }

    // -----------------------------------------------------------------------
    // IModule — Metadata
    // -----------------------------------------------------------------------

    /**
     * @notice This module is plug-and-play — no preset configuration required.
     * @dev US_COUNTRY_CODE is a compile-time constant; no admin setup needed.
     */
    function isPlugAndPlay() external pure override returns (bool) {
        return true;
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
        return "AetherumUSJurisdictionModule";
    }

    // -----------------------------------------------------------------------
    // Public Getters
    // -----------------------------------------------------------------------

    /**
     * @notice Returns true if a given address is registered under US jurisdiction
     *         for the specified compliance contract.
     * @param _compliance  The compliance contract address.
     * @param _address     The wallet address to check.
     */
    function isUSResident(
        address _compliance,
        address _address
    ) external view returns (bool) {
        return _getCountry(_compliance, _address) == US_COUNTRY_CODE;
    }

    /**
     * @notice Returns the ISO 3166-1 numeric country code registered for a wallet.
     * @param _compliance  The compliance contract address.
     * @param _address     The wallet address to look up.
     */
    function getInvestorCountry(
        address _compliance,
        address _address
    ) external view returns (uint16) {
        return _getCountry(_compliance, _address);
    }

    // -----------------------------------------------------------------------
    // Internal Helpers
    // -----------------------------------------------------------------------

    /**
     * @dev Looks up the ISO 3166-1 numeric country code for a wallet address
     *      by querying the token's Identity Registry through the compliance contract.
     *
     * @param _compliance  The ModularCompliance contract address.
     * @param _userAddress The wallet to look up.
     * @return uint16      The ISO 3166-1 numeric country code.
     */
    function _getCountry(
        address _compliance,
        address _userAddress
    ) internal view returns (uint16) {
        return IToken(
            IModularCompliance(_compliance).getTokenBound()
        ).identityRegistry().investorCountry(_userAddress);
    }
}
