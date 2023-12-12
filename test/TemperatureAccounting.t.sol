// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Vm, Test} from "forge-std/Test.sol";
import {TemperatureAccounting} from "src/./TemperatureAccounting.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract Writer {
    function write(bytes32 slot, bytes32 newVal) public {
        assembly {
            sstore(slot, newVal)
        }
    }

    function read(bytes32 slot) public view returns (bytes32) {
        bytes32 val;
        assembly {
            val := sload(slot)
        }
        return val;
    }

    function call(bytes calldata) public {}

    function _revert() public pure {
        revert("revert");
    }
}

contract TemperatureAccountingTest is Test {
    Writer writer;
    TemperatureAccounting target;

    function setUp() public {
        vm.startStateDiffRecording();
        writer = new Writer();
        target = new TemperatureAccounting();
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
        target.preprocessAccesses(diffs);
        vm.startStateDiffRecording();
        writer.call("");
        diffs = filterExtcodesize(vm.stopAndReturnStateDiff());
        assertEq(diffs.length, 1, "diffs.length");
        TemperatureAccounting.GasMeasurements memory measurements =
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
        target.preprocessAccesses(diffs);
        vm.startStateDiffRecording();
        writer.read(bytes32(0));
        diffs = filterExtcodesize(vm.stopAndReturnStateDiff());
        assertEq(diffs.length, 1, "diffs.length");
        TemperatureAccounting.GasMeasurements memory measurements =
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
        target.preprocessAccesses(diffs);

        vm.startStateDiffRecording();
        writer.write({slot: bytes32(0), newVal: bytes32(uint256(2))});
        diffs = filterExtcodesize(vm.stopAndReturnStateDiff());

        assertEq(diffs.length, 1, "diffs.length");
        TemperatureAccounting.GasMeasurements memory measurements =
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
        target.preprocessAccesses(diffs);
        vm.startStateDiffRecording();
        for (uint256 i = 0; i < 100; i++) {
            writer.write({slot: bytes32(i), newVal: bytes32(uint256(0))});
        }
        diffs = filterExtcodesize(vm.stopAndReturnStateDiff());
        assertEq(diffs.length, 100, "diffs.length");
        TemperatureAccounting.GasMeasurements memory measurements =
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
