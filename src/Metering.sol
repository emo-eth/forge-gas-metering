// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {
    NetworkTxCosts,
    AccessListEntry,
    TransactionData,
    AccessCosts,
    GasMeasurements,
    MeterCallArgs
} from "./Structs.sol";
import {Vm} from "forge-std/Test.sol";
import {TransactionOverheadUtils} from "./TransactionOverheadUtils.sol";
import {GasConsumer} from "./GasConsumer.sol";
import {AccessAccounting} from "./AccessAccounting.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title Metering
 * @author emo.eth
 * @notice Metering utils for calculating gas consumed by an external call, as
 *         if it were executed as a solo transaction by the EVM.
 *         To measure gas usage of an external function call:
 *         - Call `setUpMetering` in the `setUp` method.
 *         - Add the `manuallyMetered` modifier to all tests
 *         - Do test setup as normal
 *         - Prepare calldata for calls you wish to meter
 *         - Call `meterCallAndLog` or `meterCall` with the target, calldata,
 *           and value
 *
 */
contract Metering is TransactionOverheadUtils, GasConsumer {
    /// @dev approximate additional overhead of calling the target account that
    /// is not accounted for by AccessAccounting
    int256 constant METER_OVERHEAD = 31;
    /// @dev approximate overhead of calling the meterGas method
    int256 constant CONSUME_CALL_OVERHEAD = 275;
    /// @dev approximate overhead of running a test that touches the pause/resume cheatcodes
    /// todo: maybe cost of checking failed storage slots? debugger seems to
    /// exit immediately after modifier calls cheatcode to resume gas metering,
    /// however
    int256 constant MYSTERY_TEST_OVERHEAD = 4103; //4147;
    /// @dev convenience constant of all additional overhead
    int256 constant ALL_OVERHEAD =
        METER_OVERHEAD + CONSUME_CALL_OVERHEAD + MYSTERY_TEST_OVERHEAD;
    /// @dev selector to call the vm.pauseGasMetering cheatcode in assembly (to avoid solidity EXTCODSIZE checks)
    uint256 constant PAUSE_GAS_METERING = 0xd1a5b36f;
    /// @dev selector to call the vm.resumeGasMetering cheatcode in assembly (to avoid solidity EXTCODSIZE checks)
    uint256 constant RESUME_GAS_METERING = 0x2bcd50e0;
    /// @dev selector to call the vm.startStateDiffRecording cheatcode in assembly (to avoid solidity EXTCODSIZE checks)
    uint256 constant START_STATE_DIFF = 0xcf22e3c9;
    /// @dev selector to call the vm.startPrank cheatcode in assembly
    uint256 constant START_PRANK_SELECTOR = 0x06447d56;
    /// @dev selector to call the vm.stopPrank cheatcode in assembly
    uint256 constant STOP_PRANK_SELECTOR = 0x90c5013b;
    /// @dev selector to call the vm.expectRevert cheatcode in assembly
    uint256 constant EXPECT_REVERT_SELECTOR = 0xf4844814;
    /// @dev convenience constant to access the HEVM address in assembly
    uint256 constant VM = 0x007109709ecfa91a80626ff3989d68f67f5b1dd12d;
    Vm private constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    /// @dev When true, log more granular information about makeup gas
    /// todo: consider making an enum for even more verbose logging for
    /// debugging purposes
    bool verboseMetering;

    constructor(
        NetworkTxCosts memory networkTxCosts,
        AccessCosts memory accessCosts
    ) TransactionOverheadUtils(networkTxCosts, accessCosts) {}

    /**
     * @notice Meter gas consumed by a function, and then pause gas metering
     */
    modifier metered() virtual {
        vm.resumeGasMetering();
        _;
        // ~128 gas
        assembly ("memory-safe") {
            mstore(0, PAUSE_GAS_METERING) // ~9 gas
            pop(
                staticcall(gas(), VM, 0x1c, 0x4, 0, 0) // ~119 gas
            )
        }
    }

    modifier manuallyMetered() virtual {
        initializeCallMetering();
        _;

        assembly ("memory-safe") {
            let g := gas()
            mstore(0, RESUME_GAS_METERING)
            pop(staticcall(gas(), VM, 0x1c, 4, 0, 0))
            log1(0, 0, sub(g, gas()))
            return(0, 0)
        }
    }

    /**
     * @notice Set up a test contract for real-world gas metering. Should be called
     *         first in the setUp() method.
     * @param verbose Enables more verbose logging
     */
    function setUpMetering(bool verbose) internal {
        vm.pauseGasMetering();
        verboseMetering = verbose;
    }

    /**
     * @notice Set up an individual test method for real-world gas metering. Should
     *         be called first thing in a test.
     */
    function initializeCallMetering() internal {
        // warm the gas consumer address, or else AccessAccounting will overcharge
        // for the call to burn the makeup gas.
        makeAndMarkWarm(INVALID_ADDRESS);
        vm.startStateDiffRecording();
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
        address from,
        address to,
        bytes memory callData,
        uint256 value,
        bool transaction,
        bool expectRevert,
        string memory message
    ) internal returns (uint256, bytes memory) {
        (uint256 gasUsed, bytes memory data) =
            meterCall(from, to, callData, value, transaction, expectRevert);
        console2.log(string.concat(message, " gas used"), gasUsed);
        return (gasUsed, data);
    }

    /**
     * @notice Calculate transaction-level overhead and record gas used by evm
     *         during call, passing in a struct of arguments.
     * @param args Struct containing all arguments to meterCallAndLog
     * @param message A message to prepend to the logged gas usage
     * @return calculated adjusted gas used
     * @return return data from call
     */
    function meterCallAndLog(MeterCallArgs memory args, string memory message)
        internal
        returns (uint256, bytes memory)
    {
        return meterCallAndLog(
            args.from,
            args.to,
            args.callData,
            args.value,
            args.transaction,
            args.expectRevert,
            message
        );
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
        address from,
        address to,
        bytes memory callData,
        uint256 value,
        bool transaction,
        bool expectRevert
    ) internal returns (uint256, bytes memory) {
        Vm.AccountAccess[] memory diffs = vm.stopAndReturnStateDiff();
        preprocessAccountAccesses(diffs);
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
            // use startPrank before expect revert because it doesn't matter what address calls expectRevert,
            // and calling expectRevert before startPrank will cause the call to revert
            if iszero(iszero(from)) {
                mstore(0, START_PRANK_SELECTOR)
                mstore(0x20, from)
                pop(call(gas(), VM, 0, 0x1c, 0x24, 0, 0))
            }
            if expectRevert {
                mstore(0, EXPECT_REVERT_SELECTOR)
                pop(call(gas(), VM, 0, 0x1c, 4, 0, 0))
            }
            let succ :=
                call(gas(), to, value, add(callData, 0x20), mload(callData), 0, 0)
            let afterGas := gas()
            // pause gas metering before ending prank if active
            mstore(0, PAUSE_GAS_METERING)
            pop(call(gas(), VM, 0, 0x1c, 4, 0, 0))
            if iszero(iszero(from)) {
                mstore(0, STOP_PRANK_SELECTOR)
                pop(call(gas(), VM, 0, 0x1c, 4, 0, 0))
            }
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

        // Calculate static overhead of the call
        uint256 overheadGasCost =
            (transaction) ? getCallOverhead(to, callData) : 0;
        (uint256 makeup, uint256 finalRefund) = calcGasToBurn(
            int256(overheadGasCost),
            int256(observedGas) - METER_OVERHEAD,
            int256(measurements.evmGas),
            int256(measurements.adjustedGas),
            measurements.evmRefund,
            measurements.adjustedRefund,
            ALL_OVERHEAD
        );
        int256 targetGas = int256(observedGas) - int256(METER_OVERHEAD)
            + int256(measurements.adjustedGas) - int256(measurements.evmGas)
            - int256(measurements.adjustedRefund) + int256(overheadGasCost);
        if (verboseMetering) {
            console2.log("target gas", targetGas);

            console2.log("tx overhead gas", overheadGasCost);
            console2.log("observed gas", observedGas);
            console2.log(
                "adjusted account + storage gas", measurements.adjustedGas
            );
            console2.log("extra overhead gas", ALL_OVERHEAD);
            console2.log("evm account + storage gas", measurements.evmGas);
            console2.log("evm refund", measurements.evmRefund);
            console2.log("adjusted refund", measurements.adjustedRefund);
            console2.log("final refund", finalRefund);
            console2.log("makeup gas", makeup);
        }
        consumeAndMeterGas(makeup);
        return (uint256(targetGas), data);
    }

    /**
     * @notice Calculate transaction-level overhead and record gas used by evm
     *         during call, passing in a struct of arguments.
     * @param args Struct containing all arguments to meterCall
     * @return calculated adjusted gas used
     * @return return data from call
     */
    function meterCall(MeterCallArgs memory args)
        internal
        returns (uint256, bytes memory)
    {
        return meterCall(
            args.from,
            args.to,
            args.callData,
            args.value,
            args.transaction,
            args.expectRevert
        );
    }
}
