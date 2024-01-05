// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {Vm, Test} from "forge-std/Test.sol";
import {AccessAccounting} from "../src/AccessAccounting.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {AccessCosts, GasMeasurements} from "../src/Structs.sol";

import {
    MAINNET_BASE_ACCESS_COST,
    MAINNET_COST_COLD_ACCOUNT_ACCESS,
    MAINNET_COST_COLD_SLOAD,
    MAINNET_COST_COLD_SSTORE,
    MAINNET_COST_SSTORE_CHANGE_ORIGINAL_ZERO,
    MAINNET_COST_SSTORE_CHANGE_ORIGINAL_NON_ZERO,
    MAINNET_COST_SSTORE_CHANGE_NON_ORIGINAL,
    MAINNET_COST_INITIALIZE_ACCOUNT,
    MAINNET_REFUND_RESTORE_NON_ZERO_SLOT_TO_ZERO,
    MAINNET_REFUND_TEMP_ZERO_TO_NON_ZERO,
    MAINNET_REFUND_NON_ZERO_TO_ZERO,
    MAINNET_REFUND_RESTORE_TEMP_NON_ZERO_TO_ZERO_WARM,
    MAINNET_REFUND_RESTORE_TEMP_NON_ZERO_TO_ZERO_COLD,
    MAINNET_REFUND_RESTORE_ORIGINAL_NON_ZERO_WARM,
    MAINNET_REFUND_RESTORE_ORIGINAL_NON_ZERO_COLD
} from "../src/Constants.sol";
import {Writer} from "./Writer.sol";

contract AccessAccountingTest is Test {
    Writer writer;
    AccessAccounting target;

    function setUp() public {
        vm.startStateDiffRecording();
        writer = new Writer();
        target = new AccessAccounting(
            AccessCosts({
                baseAccessCost: MAINNET_BASE_ACCESS_COST,
                costColdAccountAccess: MAINNET_COST_COLD_ACCOUNT_ACCESS,
                costColdSload: MAINNET_COST_COLD_SLOAD,
                costColdSstore: MAINNET_COST_COLD_SSTORE,
                costSstoreChangeOriginalZero: MAINNET_COST_SSTORE_CHANGE_ORIGINAL_ZERO,
                costSstoreChangeOriginalNonZero: MAINNET_COST_SSTORE_CHANGE_ORIGINAL_NON_ZERO,
                costSstoreChangeNonOriginal: MAINNET_COST_SSTORE_CHANGE_NON_ORIGINAL,
                costInitializeAccount: MAINNET_COST_INITIALIZE_ACCOUNT,
                refundRestoreNonZeroSlotToZero: MAINNET_REFUND_RESTORE_NON_ZERO_SLOT_TO_ZERO,
                refundTempZeroToNonZero: MAINNET_REFUND_TEMP_ZERO_TO_NON_ZERO,
                refundNonZeroToZero: MAINNET_REFUND_NON_ZERO_TO_ZERO,
                refundRestoreTempNonZeroToZeroWarm: MAINNET_REFUND_RESTORE_TEMP_NON_ZERO_TO_ZERO_WARM,
                refundRestoreTempNonZeroToZeroCold: MAINNET_REFUND_RESTORE_TEMP_NON_ZERO_TO_ZERO_COLD,
                refundRestoreOriginalNonZeroWarm: MAINNET_REFUND_RESTORE_ORIGINAL_NON_ZERO_WARM,
                refundRestoreOriginalNonZeroCold: MAINNET_REFUND_RESTORE_ORIGINAL_NON_ZERO_COLD
            })
        );
    }
    /**
     * @notice Test that state diff recording works in the way we expect
     */

    function testCanary() public {
        vm.startStateDiffRecording();
        address(0x123456).call("");
        Vm.AccountAccess[] memory diffs = vm.stopAndReturnStateDiff();
        assertEq(diffs.length, 1, "diffs.length");
        vm.startStateDiffRecording();
        diffs = vm.stopAndReturnStateDiff();
        assertEq(diffs.length, 0, "diffs.length no calls");
    }

    function testCallToWarm() public {
        Vm.AccountAccess[] memory diffs = vm.stopAndReturnStateDiff();
        target.preprocessAccountAccesses(diffs);
        vm.startStateDiffRecording();
        writer.call("");
        diffs = filterExtcodesize(vm.stopAndReturnStateDiff());
        assertEq(diffs.length, 1, "diffs.length");
        GasMeasurements memory measurements =
            target.processAccountAccesses(address(0), diffs);
        emit log_named_int("evm gas", measurements.evmGas);
        emit log_named_int("adjusted gas", measurements.adjustedGas);
        emit log_named_int("evmRefund", measurements.evmRefund);
        emit log_named_int("adjustedRefund", measurements.adjustedRefund);
        assertEq(measurements.evmGas, 100, "evmGas");
        assertEq(measurements.adjustedGas, 100 + 2500, "adjustedGas");
    }

    function testReadWarm() public {
        writer.read(bytes32(0));
        Vm.AccountAccess[] memory diffs = vm.stopAndReturnStateDiff();
        target.preprocessAccountAccesses(diffs);
        vm.startStateDiffRecording();
        writer.read(bytes32(0));
        diffs = filterExtcodesize(vm.stopAndReturnStateDiff());
        assertEq(diffs.length, 1, "diffs.length");
        GasMeasurements memory measurements =
            target.processAccountAccesses(address(0), diffs);
        emit log_named_int("evm gas", measurements.evmGas);
        emit log_named_int("adjusted gas", measurements.adjustedGas);
        emit log_named_int("evmRefund", measurements.evmRefund);
        emit log_named_int("adjustedRefund", measurements.adjustedRefund);
        assertEq(measurements.evmGas, 200, "evmGas");
        assertEq(measurements.adjustedGas, 200 + 2500 + 2000, "adjustedGas");
    }

    function testWriteWarm() public {
        emit log_named_address("writer", address(writer));
        writer.write({slot: bytes32(0), newVal: bytes32(uint256(1))});
        Vm.AccountAccess[] memory diffs =
            filterExtcodesize(vm.stopAndReturnStateDiff());
        target.preprocessAccountAccesses(diffs);

        vm.startStateDiffRecording();
        writer.write({slot: bytes32(0), newVal: bytes32(uint256(2))});
        diffs = filterExtcodesize(vm.stopAndReturnStateDiff());

        assertEq(diffs.length, 1, "diffs.length");
        GasMeasurements memory measurements =
            target.processAccountAccesses(address(0), diffs);
        emit log_named_int("evm gas", measurements.evmGas);
        emit log_named_int("adjusted gas", measurements.adjustedGas);
        emit log_named_int("evmRefund", measurements.evmRefund);
        emit log_named_int("adjustedRefund", measurements.adjustedRefund);
        assertEq(measurements.evmGas, 200, "evmGas");
        assertEq(measurements.adjustedGas, 7600, "adjustedGas");
    }

    function testHugeRefund() public {
        for (uint256 i = 0; i < 100; i++) {
            writer.write({slot: bytes32(i), newVal: bytes32(uint256(1))});
        }
        Vm.AccountAccess[] memory diffs =
            filterExtcodesize(vm.stopAndReturnStateDiff());
        target.preprocessAccountAccesses(diffs);
        vm.startStateDiffRecording();
        for (uint256 i = 0; i < 100; i++) {
            writer.write({slot: bytes32(i), newVal: bytes32(uint256(0))});
        }
        diffs = filterExtcodesize(vm.stopAndReturnStateDiff());
        assertEq(diffs.length, 100, "diffs.length");
        GasMeasurements memory measurements =
            target.processAccountAccesses(address(writer), diffs);
        emit log_named_int("evm gas", measurements.evmGas);
        emit log_named_int("adjusted gas", measurements.adjustedGas);
        emit log_named_int("evmRefund", measurements.evmRefund);
        emit log_named_int("adjustedRefund", measurements.adjustedRefund);
        // assertEq(measurements.evmGas, 200, "evmGas");
        // assertEq(measurements.adjustedGas, 7600, "adjustedGas");
    }

    function filterExtcodesize(Vm.AccountAccess[] memory accesses)
        internal
        pure
        returns (Vm.AccountAccess[] memory)
    {
        Vm.AccountAccess[] memory filtered =
            new Vm.AccountAccess[](accesses.length);
        uint256 size;
        for (uint256 i = 0; i < accesses.length; ++i) {
            if (accesses[i].kind != VmSafe.AccountAccessKind.Extcodesize) {
                filtered[size] = accesses[i];
                ++size;
            }
        }
        assembly {
            mstore(filtered, size)
        }
        return filtered;
    }

    function emptyAccountAccess()
        internal
        pure
        returns (Vm.AccountAccess memory access)
    {}

    function emptyStorageAccess()
        internal
        pure
        returns (Vm.StorageAccess memory access)
    {}
}
