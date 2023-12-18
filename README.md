# forge-gas-metering

`forge-gas-metering` is a (WIP, experimental) library that tries to get forge to report realistic gas numbers in tests (for use with `forge snapshot`, etc).

## Usage

To overload forge gas metering, inherit from one of the `Metering` contracts, and call `setUpMetering(bool verbose)` in the `setUp` method.

Then, add the `manuallyMetered` modifier to all tests. **Note that forge will report huge numbers for all tests that do not include this modifier or else call `vm.resumeGasMetering` on their own.**

Within a test, perform setup and assertions as normal, but wrap calls you wish to meter with either the `meterCall` or `meterCallAndLog` methods. This requires manually encoding the calldata to pass

Here is a simple example:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Metering} from "src/Metering.sol";

contract MeteringTest is Metering {
    function setUp() public {
        setUpMetering({verbose: false});
    }

    function testManualMetering() public manuallyMetered {
        meterCallAndLog({
            to: address(0x123456),
            callData: hex"000001",
            value: 0,
            transaction: true,
            message: "manual"
        });
    }
}
```

## Configuring

See `MainnetMetering` and `OpStackMetering` for examples of how to configure the base `Metering` contract for different networks.

## Notes

Metering is imperfect – it will be off by up to 200 gas. Ideally, it should over-count gas, but this seems to vary per test contract and compiler settings. The `OVERHEAD` constants in `Metering.sol` can probably be better finetuned to account for this.

There are probably bugs.
