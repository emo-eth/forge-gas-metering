// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Metering} from "./Metering.sol";

contract MainnetMetering is
    // zero bytes
    Metering(
        4,
        // non-zero bytes
        16,
        // flat tx
        21000,
        // access list address
        2400,
        // access list storage key
        1900
    )
{}
