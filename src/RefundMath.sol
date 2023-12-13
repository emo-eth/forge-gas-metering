// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {console2} from "forge-std/console2.sol";
import {TransactionOverheadUtils} from "./TransactionOverheadUtils.sol";

abstract contract RefundMath is TransactionOverheadUtils {
    int256 constant REFUND_DENOM = 5;

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
    ) internal view virtual returns (uint256 gasToBurn) {
        console2.log("target gas spend:");
        console2.logInt(
            observedGas + adjustedAccessGas - evmAccessGas - adjustedRefund
                + callOverheadGas
        );
        // observedGas += testOverhead;
        // adjustedAccessGas -= testOverhead;
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
            int256 maxRefundLte = totalGasLte / REFUND_DENOM;
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
                return uint256(gasToBurnIfEvmRefundLteMaxRefund);
            }
        }
        // otherwise, some Refund_final < Refund_evm will be credited after tx
        // todo: this increases refund by Gas_testOverhead / REFUND_DENOMINATOR
        // Gas_forge* = Gas_observed + Gas_testOverhead + Gas_forgeCallOverhead
        // Gas_total* = Gas_forge* + Gas_makeup + Gas_callOverhead
        // Refund_final* = Gas_total* / REFUND_DENOM
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
        // Gas_testOverhead + Gas_makeup - (Gas_total* / REFUND_DENOM) = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_testOverhead + Gas_makeup - ((Gas_forge* + Gas_makeup + Gas_callOverhead) / REFUND_DENOM) = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_testOverhead + Gas_makeup - (((Gas_observed + Gas_testOverhead + Gas_forgeCallOverhead) + Gas_makeup + Gas_callOverhead) / REFUND_DENOM) = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted
        // Gas_makeup - (((Gas_observed + Gas_testOverhead + Gas_forgeCallOverhead) + Gas_makeup + Gas_callOverhead) / REFUND_DENOM) = Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted - Gas_testOverhead
        // (REFUND_DENOM - 1) * Gas_makeup - (Gas_obsered + Gas_testOverhead + Gas_forgeCallOverhead + Gas_callOverhead) = REFUND_DENOM * (Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted - Gas_testOverhead)
        // (REFUND_DENOM - 1) * Gas_makeup = REFUND_DENOM * (Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted - Gas_testOverhead) + (Gas_obsered + Gas_testOverhead + Gas_forgeCallOverhead + Gas_callOverhead)
        // Gas_makeup = (REFUND_DENOM * (Gas_adjustedAccess - Gas_evmAccess - Refund_adjusted - Gas_testOverhead) + (Gas_obsered + Gas_testOverhead + Gas_forgeCallOverhead + Gas_callOverhead)) / (REFUND_DENOM - 1)
        int256 gasToBurnIfEvmRefundGtMaxRefund = (
            REFUND_DENOM
                * (
                    adjustedAccessGas - evmAccessGas - adjustedRefund
                        - testOverheadGas
                ) + observedGas + callOverheadGas + forgeCalloverheadGas
                + testOverheadGas
        ) / (REFUND_DENOM - 1);
        // account for callOverheadGas
        gasToBurnIfEvmRefundGtMaxRefund += callOverheadGas;
        if (gasToBurnIfEvmRefundGtMaxRefund < 0) {
            console2.log(
                "gasToBurnIfEvmRefundGtMaxRefund < 0. Gas reporting will be inaccurate. Gas to burn:"
            );
            console2.logInt(gasToBurnIfEvmRefundGtMaxRefund);
            gasToBurnIfEvmRefundGtMaxRefund = 0;
        }
        return uint256(gasToBurnIfEvmRefundGtMaxRefund);
    }

    function getForgeOverheadCallGas() internal view returns (int256) {
        return int256(getCallOverhead({to: address(this), callData: msg.data}));
    }
}
