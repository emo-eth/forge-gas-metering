// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract GasConsumer {
    // approximate overhead of calling consumeGas, which may vary depending on compiler settings
    uint256 public constant CONSUME_OVERHEAD = 200;

    function consumeGas(uint256 amount) public view {
        assembly {
            // __invalid() selector
            mstore(0, 0x4e0c4813)
            pop(
                staticcall(
                    // zero out if CONSUME_OVERHEAD > amount
                    mul(
                        gt(amount, CONSUME_OVERHEAD),
                        sub(amount, CONSUME_OVERHEAD)
                    ),
                    address(),
                    0x1c,
                    0x4,
                    0,
                    0
                )
            )
        }
    }

    function __invalid() external pure {
        assembly {
            invalid()
        }
    }
}
