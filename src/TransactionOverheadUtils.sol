// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {AccessAccounting} from "./AccessAccounting.sol";
import {
    AccessListEntry,
    TransactionData,
    NetworkTxCosts,
    AccessCosts
} from "./Structs.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title TransactionOverheadUtils
 * @author emo.eth
 * @notice Utils for calculating transaction overhead.
 */
contract TransactionOverheadUtils is AccessAccounting {
    uint256 immutable CALLDATA_ZERO_BYTE_COST;
    uint256 immutable CALLDATA_NON_ZERO_BYTE_COST;
    uint256 immutable FLAT_TX_COST;
    uint256 immutable ACCESS_LIST_ADDRESS_COST;
    uint256 immutable ACCESS_LIST_STORAGE_KEY_COST;
    int256 immutable MAX_REFUND_DENOM;

    constructor(
        NetworkTxCosts memory networkTxCosts,
        AccessCosts memory accessCosts
    ) AccessAccounting(accessCosts) {
        CALLDATA_ZERO_BYTE_COST = networkTxCosts.calldataZeroByteCost;
        CALLDATA_NON_ZERO_BYTE_COST = networkTxCosts.calldataNonZeroByteCost;
        FLAT_TX_COST = networkTxCosts.flatTxCost;
        ACCESS_LIST_ADDRESS_COST = networkTxCosts.accessListAddressCost;
        ACCESS_LIST_STORAGE_KEY_COST = networkTxCosts.accessListStorageKeyCost;
        MAX_REFUND_DENOM = int256(networkTxCosts.maxRefundDenominator);
    }

    /**
     * @notice Calculates the amount of gas to burn to make up for the difference between the observed and ~real-world gas usage of a call, with adjustments so Forge reports the actual real-world number.
     * @param callOverheadGas Static gas cost of the measured call, including flat tx fee and calldata costs
     * @param observedGas Gas usage as measured by the EVM
     * @param evmAccessGas Calculated account and storage access gas usage as seen by the current EVM context
     * @param adjustedAccessGas Calculated account and storage access gas usage as seen by a hypothetical "new" EVM context, where all non-precompile accounts and their storage slots are initially cold.
     * @param evmRefund Calculated post-execution refund as seen by the current EVM context
     * @param adjustedRefund Calculated post-execution refund as seen by a hypothetical "new" EVM context
     */
    function calcGasToBurn(
        int256 callOverheadGas,
        int256 observedGas,
        int256 evmAccessGas,
        int256 adjustedAccessGas,
        int256 evmRefund,
        int256 adjustedRefund,
        int256 testOverheadGas
    ) internal view virtual returns (uint256 gasToBurn, uint256 finalRefund) {
        int256 forgeCalloverheadGas = getForgeOverheadCallGas();
        {
            // first, assume all of of evmRefund will be credited after tx
            // Gas_forge* = Gas_observed + Gas_testOverhead + Gas_forgeCallOverhead
            // Gas_total* = Gas_forge* + Gas_makeup + Gas_callOverhead
            // Gas_final* = Gas_total* - Refund_evm
            // Gas_reported* = Gas_final* - Gas_forgeCallOverhead
            // end goal is:
            // Gas_reported* = Gas_callOverhead + Gas_observed + Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
            // substitute and solve:
            // Gas_final* - Gas_forgeCallOverhead = Gas_observed + Gas_adjustedAccess + Gas_callOverhead - Gas_evmAccess - Refund_adjusted
            // Gas_total* - Refund_evm - Gas_forgeCallOverhead = Gas_observed + Gas_adjustedAccess + Gas_callOverhead - Gas_evmAccess - Refund_adjusted
            // Gas_forge* + Gas_makeup + Gas_callOverhead - Refund_evm - Gas_forgeCallOverhead = Gas_observed + Gas_adjustedAccess + Gas_callOverhead - Gas_evmAccess - Refund_adjusted
            // Gas_observed + Gas_testOverhead + Gas_forgeCallOverhead + Gas_makeup + Gas_callOverhead - Refund_evm - Gas_forgeCallOverhead = Gas_observed + Gas_adjustedAccess + Gas_callOverhead - Gas_evmAccess - Refund_adjusted
            // Gas_observed + Gas_testOverhead + Gas_makeup + Gas_callOverhead - RefundEvm = Gas_observed + Gas_adjustedAccess + Gas_callOverhead - Gas_evmAccess - Refund_adjusted
            // Gas_makeup = Gas_observed + Gas_adjustedAccess + Gas_callOverhead - Gas_evmAccess - Refund_adjusted - Gas_observed - Gas_callOverhead + Refund_evm - Gas_testOverhead
            // Gas_makeup = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted + Refund_evm - Gas_testOverhead
            int256 gasToBurnIfEvmRefundLteMaxRefund = adjustedAccessGas
                - evmAccessGas - adjustedRefund + evmRefund - testOverheadGas;
            int256 totalGasLte =
                observedGas + gasToBurnIfEvmRefundLteMaxRefund + callOverheadGas;
            int256 maxRefundLte = totalGasLte / MAX_REFUND_DENOM;
            // if evmRefund <= maxRefund, then all of evmRefund will be credited after tx
            bool evmRefundLteMaxRefund = evmRefund <= maxRefundLte;
            if (evmRefundLteMaxRefund) {
                // account for callOverheadGas
                gasToBurnIfEvmRefundLteMaxRefund += callOverheadGas;
                if (gasToBurnIfEvmRefundLteMaxRefund < 0) {
                    console2.log(
                        "gasToBurnIfEvmRefundLteMaxRefund < 0. Gas reporting will be inaccurate. Gas to burn:"
                    );
                    console2.logInt(gasToBurnIfEvmRefundLteMaxRefund);
                    gasToBurnIfEvmRefundLteMaxRefund = 0;
                }
                return (
                    uint256(gasToBurnIfEvmRefundLteMaxRefund),
                    uint256(evmRefund)
                );
            }
        }
        // otherwise, some Refund_final < Refund_evm will be credited after tx
        // todo: this increases refund by Gas_testOverhead / REFUND_DENOMINATOR
        // Gas_forge* = Gas_observed + Gas_testOverhead + Gas_forgeCallOverhead
        // Gas_total* = Gas_forge* + Gas_makeup + Gas_callOverhead
        // Refund_final* = Gas_total* / MAX_REFUND_DENOM
        // Gas_final* = Gas_total* - Refund_final*
        // Gas_reported* = Gas_final* - Gas_forgeCallOverhead
        // end goal is:
        // Gas_reported* = Gas_callOverhead + Gas_observed + Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // substitute and solve:
        // Gas_final* - Gas_forgeCallOverhead = Gas_callOverhead + Gas_observed + Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_total* - Refund_final* - Gas_forgeCallOverhead = Gas_callOverhead + Gas_observed + Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_forge* + Gas_makeup + Gas_callOverhead - Refund_final* - Gas_forgeCallOverhead = Gas_callOverhead + Gas_observed + Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_forge* + Gas_makeup  - Refund_final* - Gas_forgeCallOverhead = Gas_observed + Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // (Gas_observed + Gas_testOverhead + Gas_forgeCalloverhead) + Gas_makeup - Refund_final* - Gas_forgeCallOverhead = Gas_observed + Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_testOverhead + Gas_makeup - Refund_final* = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_testOverhead + Gas_makeup - (Gas_total* / MAX_REFUND_DENOM) = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_testOverhead + Gas_makeup - ((Gas_forge* + Gas_makeup + Gas_callOverhead) / MAX_REFUND_DENOM) = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_testOverhead + Gas_makeup - (((Gas_observed + Gas_testOverhead + Gas_forgeCallOverhead) + Gas_makeup + Gas_callOverhead) / MAX_REFUND_DENOM) = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_makeup - (((Gas_observed + Gas_testOverhead + Gas_forgeCallOverhead) + Gas_makeup + Gas_callOverhead) / MAX_REFUND_DENOM) = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted - Gas_testOverhead
        // (MAX_REFUND_DENOM - 1) * Gas_makeup - (Gas_obsered + Gas_testOverhead + Gas_forgeCallOverhead + Gas_callOverhead) = MAX_REFUND_DENOM * (Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted - Gas_testOverhead)
        // (MAX_REFUND_DENOM - 1) * Gas_makeup = MAX_REFUND_DENOM * (Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted - Gas_testOverhead) + (Gas_obsered + Gas_testOverhead + Gas_forgeCallOverhead + Gas_callOverhead)
        // Gas_makeup = (MAX_REFUND_DENOM * (Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted - Gas_testOverhead) + (Gas_obsered + Gas_testOverhead + Gas_forgeCallOverhead + Gas_callOverhead)) / (MAX_REFUND_DENOM - 1)
        int256 gasToBurnIfEvmRefundGtMaxRefund = (
            MAX_REFUND_DENOM
                * (
                    adjustedAccessGas - evmAccessGas - adjustedRefund
                        - testOverheadGas
                ) + observedGas + callOverheadGas + forgeCalloverheadGas
                + testOverheadGas
        ) / (MAX_REFUND_DENOM - 1);
        // account for callOverheadGas
        gasToBurnIfEvmRefundGtMaxRefund += callOverheadGas;
        if (gasToBurnIfEvmRefundGtMaxRefund < 0) {
            console2.log(
                "gasToBurnIfEvmRefundGtMaxRefund < 0. Gas reporting will be inaccurate. Gas to burn:"
            );
            console2.logInt(gasToBurnIfEvmRefundGtMaxRefund);
            gasToBurnIfEvmRefundGtMaxRefund = 0;
        }
        return (
            uint256(gasToBurnIfEvmRefundGtMaxRefund),
            uint256(
                (
                    observedGas + testOverheadGas + forgeCalloverheadGas
                        + gasToBurnIfEvmRefundGtMaxRefund + callOverheadGas
                ) / MAX_REFUND_DENOM
                )
        );
    }

    function getForgeOverheadCallGas() internal view returns (int256) {
        AccessListEntry[] memory entries;
        return int256(
            getForgeCallOverhead(
                TransactionData({
                    to: address(this),
                    callData: msg.data,
                    accessListEntries: entries
                })
            )
        );
    }

    function getCallOverhead(address to, bytes memory callData)
        internal
        view
        returns (uint256)
    {
        AccessListEntry[] memory entries;
        return getCallOverhead(TransactionData(to, callData, entries));
    }

    function getCallOverhead(TransactionData memory txData)
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 cost = FLAT_TX_COST;
        unchecked {
            cost += getAccessListCost(txData.accessListEntries);
            cost += callDataCost(txData.callData);
        }
        return cost;
    }

    function getForgeCallOverhead(TransactionData memory txData)
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 cost = FLAT_TX_COST;
        unchecked {
            cost += getAccessListCost(txData.accessListEntries);
            cost += mainnetCallDataCost(txData.callData);
        }
        return cost;
    }

    function getAccessListCost(AccessListEntry[] memory entries)
        internal
        view
        returns (uint256)
    {
        uint256 cost;
        unchecked {
            cost += entries.length * ACCESS_LIST_ADDRESS_COST;
        }
        for (uint256 i; i < entries.length; ++i) {
            unchecked {
                cost +=
                    entries[i].storageKeys.length * ACCESS_LIST_STORAGE_KEY_COST;
            }
        }
        return cost;
    }

    function mainnetCallDataCost(bytes memory callData)
        internal
        view
        returns (uint256)
    {
        bytes memory transformed = callData;
        uint256 cost;
        for (uint256 i; i < transformed.length;) {
            unchecked {
                cost += (transformed[i] == 0)
                    ? CALLDATA_ZERO_BYTE_COST
                    : CALLDATA_NON_ZERO_BYTE_COST;
                ++i;
            }
        }
        return cost;
    }

    function callDataCost(bytes memory callData)
        internal
        view
        virtual
        returns (uint256)
    {
        return mainnetCallDataCost(callData);
    }

    /**
     * @notice Preprocess calldata according to network rules, eg, Arbitrum
     *         first compresses calldata, then charges 4 gas per byte.
     * @param callData The calldata to preprocess.
     */
    function preprocessCalldata(bytes memory callData)
        internal
        pure
        virtual
        returns (bytes memory)
    {
        return callData;
    }
}
