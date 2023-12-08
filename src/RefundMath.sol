// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract RefundMath {
    int256 constant REFUND_DENOM = 5;

    function calcGasMakeupWithRefund(
        int256 callOverheadGas,
        int256 measuredGas,
        int256 evmGas,
        int256 adjustedGas,
        int256 evmRefund,
        int256 adjustedRefund
    ) internal pure returns (uint256 gasToBurn) {
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

        return uint256(gasToBurnIfEvmRefundGtMaxRefund);
    }

    /**
     * @notice Calculates the gas used given gas measurements
     * @param callOverheadGas Static tx gas overhead cost
     * @param measuredGas Measured gas usage by evm
     * @param evmGas Storage and account-access related gas usage as the EVM would report it
     * @param adjustedGas Storage and account-access related gas usage adjusted for slots/accounts touched by test setup
     * @param evmRefund Storage-related refund as the EVM would report it
     * @param adjustedRefund Storage-related refund adjusted for slots touched by test setup
     */
    function calcGasUsedForManualReporting(
        int256 callOverheadGas,
        int256 measuredGas,
        int256 evmGas,
        int256 adjustedGas,
        int256 evmRefund,
        int256 adjustedRefund
    ) internal pure returns (uint256 gasMakeup) {
        // Gas_total = Gas_measured + Gas_overhead - Gas_evm + Gas_adjusted - Refund_adjusted
    }
}
