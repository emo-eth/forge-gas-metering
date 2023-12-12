// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    NetworkTxCosts,
    AccessListEntry,
    TransactionData,
    AccessCosts,
    GasMeasurements
} from "./Structs.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {TransactionOverheadUtils} from "./TransactionOverheadUtils.sol";
import {GasConsumer} from "./GasConsumer.sol";
import {AccessAccounting} from "./AccessAccounting.sol";
import {RefundMath} from "./RefundMath.sol";

/**
 * @title Metering
 * @author emo.eth
 * @notice Metering utils for calculating gas consumed by an external call, as
 *         if it were executed as a solo transaction by the EVM.
 *         To measure gas usage of an external function call:
 *         - Call `vm.pauseGasMetering` before *any* test setup is done, ie, as
 *           the first line of the `setUp` function.
 *         - Do test setup as normal
 *         - Prepare all calldata
 *         - Call `meterCallAndLog` or `meterCall` with the target, calldata,
 *           and value
 *         - Call `vm.resumeGasMetering` afterwards to deal with annoying
 *           Foundry bugs
 *
 */
contract Metering is
    TransactionOverheadUtils,
    GasConsumer,
    AccessAccounting,
    RefundMath,
    Test
{
    int256 constant METER_OVERHEAD = 31;
    uint256 constant TEST_OVERHEAD = 6344;
    uint256 constant PAUSE_GAS_METERING = 0xd1a5b36f;
    uint256 constant RESUME_GAS_METERING = 0x2bcd50e0;
    uint256 constant START_STATE_DIFF = 0xcf22e3c9;
    uint256 constant VM = 0x007109709ecfa91a80626ff3989d68f67f5b1dd12d;
    bool verboseMetering;

    constructor(
        NetworkTxCosts memory networkTxCosts,
        AccessCosts memory accessCosts
    ) TransactionOverheadUtils(networkTxCosts) AccessAccounting(accessCosts) {}

    /**
     * @notice Meter gas consumed by a function, and then pause gas metering
     */
    modifier metered() virtual {
        vm.resumeGasMetering();
        _;
        vm.pauseGasMetering();
    }

    modifier manuallyMetered() virtual {
        _;
        vm.resumeGasMetering();
    }

    function setUpMetering(bool verbose) internal {
        vm.pauseGasMetering();
        verboseMetering = verbose;
        vm.startStateDiffRecording();
        setUpGasConsumer();
    }

    /**
     * @notice Add approximately gasCost units of gas to Foundry's gas meter.
     *         Resumes and then pauses gas metering.
     * @param gasCost The total gas cost to meter
     */
    function consumeAndMeterGas(uint256 gasCost) internal metered {
        consumeGas(gasCost);
    }

    /**
     * @notice Calculate transaction-level overhead and record gas used by evm during call.
     *         Explicitly consume the gas cost of the call plus the static overhead when `transaction` is true.
     *         Emits a log with the given message and the gas used.
     *         Assumes paused gas metering.
     * @param to The address to call
     * @param callData The calldata to send
     * @param value The value to send
     * @param transaction Whether or not this should add static overhead for a transaction
     * @param message A message to prepend to the logged gas usage
     */
    function meterCallAndLog(
        address to,
        bytes memory callData,
        uint256 value,
        bool transaction,
        string memory message
    ) internal returns (uint256, bytes memory) {
        (uint256 gasUsed, bytes memory data) =
            meterCall(to, callData, value, transaction);
        emit log_named_uint(string.concat(message, " gas used"), gasUsed);
        return (gasUsed, data);
    }

    /**
     * @notice Calculate transaction-level overhead and record gas used by evm during call.
     *         Explicitly consume the gas cost of the call plus the static overhead when `transaction` is true.
     *         Assumes paused gas metering.
     * @param to The address to call
     * @param callData The calldata to send
     * @param value The value to send
     * @param transaction Whether or not this should add static overhead for a transaction
     */
    function meterCall(
        address to,
        bytes memory callData,
        uint256 value,
        bool transaction
    ) internal returns (uint256, bytes memory) {
        // Calculate static overhead of the call
        uint256 overheadGasCost =
            (transaction) ? getCallOverhead(to, callData) : 0;

        Vm.AccountAccess[] memory diffs = vm.stopAndReturnStateDiff();
        preprocessAccesses(diffs);

        // track evm gas usage
        uint256 observedGas;
        uint256 returndataSize;
        assembly ("memory-safe") {
            // call cheatcodes in assembly to avoid solc inserting unnecessary EXTCODESIZE checks
            mstore(0, START_STATE_DIFF)
            pop(call(gas(), VM, 0, 0x1c, 4, 0, 0))
            mstore(0, RESUME_GAS_METERING)
            pop(call(gas(), VM, 0, 0x1c, 4, 0, 0))
            let startingGas := gas()
            let succ :=
                call(gas(), to, value, add(callData, 0x20), mload(callData), 0, 0)
            let afterGas := gas()
            mstore(0, PAUSE_GAS_METERING)
            pop(call(gas(), VM, 0, 0x1c, 4, 0, 0))
            observedGas := sub(startingGas, afterGas)

            if iszero(succ) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            // copy return data, if any
            returndataSize := returndatasize()
        }
        bytes memory data = new bytes(returndataSize);
        assembly ("memory-safe") {
            returndatacopy(add(data, 0x20), 0, returndatasize())
        }

        diffs = vm.stopAndReturnStateDiff();
        GasMeasurements memory measurements = processAccountAccesses(to, diffs);
        uint256 makeup = calcMakeupGasToBurn(
            int256(overheadGasCost),
            int256(observedGas + TEST_OVERHEAD),
            int256(measurements.evmGas),
            int256(
                measurements.adjustedGas - int256(TEST_OVERHEAD)
                    - METER_OVERHEAD
            ),
            measurements.evmRefund,
            measurements.adjustedRefund
        );

        if (verboseMetering) {
            emit log_named_uint("tx overhead gas", overheadGasCost);
            emit log_named_uint("observed gas", observedGas);
            emit log_named_int(
                "adjusted account + storage gas", measurements.adjustedGas
            );
            emit log_named_int(
                "adjusted overhead gas", METER_OVERHEAD + int256(TEST_OVERHEAD)
            );
            emit log_named_int("evm account + storage gas", measurements.evmGas);
            emit log_named_int("evm refund", measurements.evmRefund);
            emit log_named_int("adjusted refund", measurements.adjustedRefund);
            emit log_named_uint("makeup gas", makeup);
        }

        consumeAndMeterGas(makeup);
        return (observedGas + makeup + uint256(TEST_OVERHEAD), data);
    }
}
