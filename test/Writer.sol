// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

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
