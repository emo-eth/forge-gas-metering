// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {console2} from "forge-std/console2.sol";

contract RefundMath {
    int256 constant REFUND_DENOM = 5;

    function calcMakeupGasToBurn(
        int256 callOverheadGas,
        int256 measuredGas,
        int256 evmGas,
        int256 adjustedGas,
        int256 evmRefund,
        int256 adjustedRefund
    ) internal pure virtual returns (uint256 gasToBurn) {
        // first, assume all of of evmRefund will be credited after tx
        // Gas_total = Gas_measured + Gas_burn + Gas_overhead
        // Gas_final = Gas_total - Refund_evm
        // end goal is:
        // Gas_final = Gas_measured + Gas_adjusted - Gas_evm - Refund_adjusted + Gas_overhead
        // substitute and solve:
        // Gas_total - Refund_evm = Gas_measured + Gas_adjusted - Gas_evm - Refund_adjusted + Gas_overhead
        // Gas_measured + Gas_burn + Gas_overhead - Refund_evm = Gas_measured + Gas_adjusted - Gas_evm - Refund_adjusted + Gas_overhead
        // Gas_burn - Refund_evm = Gas_adjusted - Gas_evm - Refund_adjusted
        // Gas_burn = Gas_adjusted - Gas_evm - Refund_adjusted + Refund_evm
        int256 gasToBurnIfEvmRefundLteMaxRefund =
            adjustedGas - evmGas - adjustedRefund + evmRefund;
        int256 totalGasLte =
            measuredGas + gasToBurnIfEvmRefundLteMaxRefund + callOverheadGas;
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
        // otherwise, some Refund_final < Refund_evm will be credited after tx
        // Gas_total = Gas_measured + Gas_burn + Gas_overhead
        // Refund_final = Gas_total / REFUND_DENOM => Refund_final = (Gas_measured + Gas_burn + Gas_overhead) / REFUND_DENOM
        // Gas_final = Gas_total - Refund_final
        // end goal is:
        // Gas_final                                                          = Gas_measured + Gas_adjusted - Gas_evm - Refund_adjusted + Gas_overhead
        // substitute and solve:
        // Gas_total - Refund_final                                           = Gas_measured + Gas_adjusted - Gas_evm - Refund_adjusted + Gas_overhead
        // Gas_measured + Gas_burn + Gas_overhead - Refund_final              = Gas_measured + Gas_adjusted - Gas_evm - Refund_adjusted + Gas_overhead
        // Gas_burn - Refund_final                                            = Gas_adjusted - Gas_evm - Refund_adjusted
        // Gas_burn - (Gas_measured + Gas_burn + Gas_overhead) / REFUND_DENOM = Gas_adjusted - Gas_evm - Refund_adjusted
        // REFUND_DENOM * Gas_burn - Gas_measured - Gas_burn - Gas_overhead   = REFUND_DENOM * (Gas_adjusted - Gas_evm - Refund_adjusted)
        // REFUND_DENOM * Gas_burn - Gas_burn                                 = REFUND_DENOM * (Gas_adjusted - Gas_evm - Refund_adjusted) + Gas_measured + Gas_overhead
        // Gas_burn * (REFUND_DENOM - 1)                                      = REFUND_DENOM * (Gas_adjusted - Gas_evm - Refund_adjusted) + Gas_measured + Gas_overhead
        // Gas_burn                                                           = (REFUND_DENOM * (Gas_adjusted - Gas_evm - Refund_adjusted) + Gas_measured + Gas_overhead) / (REFUND_DENOM - 1)
        int256 gasToBurnIfEvmRefundGtMaxRefund = (
            REFUND_DENOM * (adjustedGas - evmGas - adjustedRefund) + measuredGas
                + callOverheadGas
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
}
