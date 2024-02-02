// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

/**
 * @title  GasConsumer
 * @author emo.eth
 * @notice Base contract that deploys a contract with a single INVALID opcode,
 *         which, when called, will consume all gas forwarded in constant time.
 *         Meant to be used in tests for manual gas accounting, which should
 *         also warm the account before beginning manual accounting, or else
 *         incur an extra 2500 gas for the first call.
 */
contract GasConsumer {
    uint256 constant CONSUME_OVERHEAD = 160;
    address immutable INVALID_ADDRESS;

    constructor() {
        address invalidAddress;
        assembly {
            mstore(0, 0x60008060FE81159253F3)
            invalidAddress := create2(0, 0x16, 10, 0)
            calldatacopy(calldatasize(), calldatasize(), iszero(invalidAddress))
        }
        INVALID_ADDRESS = invalidAddress;
    }

    /**
     * @notice Consume an amount of gas in constant time. With optimizer
     *         enabled, and INVALID_ADDRESS already warmed, it should be
     *         accurate within 33 gas units if the amount is greater than
     *         CONSUME_OVERHEAD (160 gas units)
     *         Low runs + no IR will over-spend by a max of 33 gas units
     *         High runs + IR will under-spend by a max of 33 gas units
     * @param amount The amount of gas to consume, += 33 depending on compiler
     *               settings
     */
    function consumeGas(uint256 amount) internal view {
        address invalidAddress = INVALID_ADDRESS;
        assembly ("memory-safe") {
            pop(
                staticcall( // zero out if CONSUME_OVERHEAD > amount
                    mul(
                        gt(amount, CONSUME_OVERHEAD),
                        sub(amount, CONSUME_OVERHEAD)
                    ),
                    invalidAddress,
                    0,
                    0,
                    0,
                    0
                )
            )
        }
    }
}
