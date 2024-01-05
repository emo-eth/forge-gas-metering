# forge-gas-metering

`forge-gas-metering` is a (WIP, experimental) library that tries to get forge to report realistic gas numbers in tests (for use with `forge snapshot`, etc).

## Background

Forge's native gas metering is inaccurate in the following scenarios (see [this issue](https://github.com/foundry-rs/foundry/issues/6590) for more context):

- Solidity function dispatch overhead can lead to [misleading numbers](https://github.com/foundry-rs/foundry/issues/6164) when comparing tests for different (eg, pure) functions
- Forge technically underreports actual gas usage by [omitting call and calldata overhead](https://github.com/foundry-rs/foundry/issues/6578)
- But EVM storage refunds incurred as part of execution are [credited against total measured gas usage](https://github.com/foundry-rs/foundry/issues/6578)
- Accounts and slots warmed by test setup remain warm when executing target functions, and there is [no reliable way to forcibly mark accounts and slots as "cold."](https://github.com/foundry-rs/foundry/pull/5852#issuecomment-1736207581) This means that even when manually metering gas using `vm.pause/resumeGasMetering` cheatcodes, gas is underreported
- Calls within Forge's test context do not incur calldata costs
- No support for [Access Lists](https://eips.ethereum.org/EIPS/eip-2930)

`forge-gas-metering` does the following:
- pauses gas metering as part of `setUp()`
- records all accounts and storage slots warmed via Access Lists
- records all accounts and storage slots accessed during test setup
- records all accounts and storage slots accessed during actual execution
- compares execution and setup accesses and manually tracks the difference in expected gas usage as well as expected gas refunds
- burns an amount of gas such that `Gas_forgeReported ~= Gas_txOverhead + Gas_calldataOverhead + Gas_observed + (Gas_realisticAccessCosts - Gas_forgeReportedAccessCosts) - Gas_realisticRefund`

## Usage

To overload forge gas metering, inherit from one of the `Metering` contracts, and call `setUpMetering(bool verbose)` in the `setUp` method.

Then, add the `manuallyMetered` modifier to all tests. **Note that forge will report huge numbers for all tests that do not include this modifier or else call `vm.resumeGasMetering` on their own.**

Within a test, perform setup and assertions as normal, but wrap calls you wish to meter with either the `meterCall` or `meterCallAndLog` methods. This requires manually encoding the calldata to pass to the fuction.

Here is a simple example:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {MainnetMetering} from "src/MainnetMetering.sol";

contract MeteringTest is MainnetMetering, Test {
    function setUp() public {
        setUpMetering({verbose: false});
    }

    function testManualMetering() public manuallyMetered {
        meterCallAndLog({
            to: address(0x123456),
            callData: hex"000001",
            value: 0,
            transaction: true,
            message: "myFunction"
        });
    }
}
```

## Configuring

See `MainnetMetering` and `OpStackMetering` for examples of how to configure the base `Metering` contract for different networks.

## Notes

Metering is imperfect – it will be off by up to 200 gas. Ideally, it should over-count gas, but this seems to vary per test contract and compiler settings. The `OVERHEAD` constants in `Metering.sol` can probably be better finetuned to account for this.

**There are probably (many) bugs.**
