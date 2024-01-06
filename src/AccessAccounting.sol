// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import {Test, Vm} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {AccessCosts, GasMeasurements, AccessListEntry} from "./Structs.sol";

/**
 * @title AccessAccounting
 * @author emo.eth
 * @notice Helpers for manually accounting for gas accounting differences based
 *         on account and storage slot "warmth."
 *         TODO: Support multiple forks/chainId accounting.
 */
contract AccessAccounting {
    uint256 constant ACCESS_ACCOUNTING_SLOT =
        uint256(keccak256("AccessAccounting")) - 1;
    int256 immutable COST_BASE_ACCESS;
    int256 immutable COST_COLD_ACCOUNT_ACCESS;
    int256 immutable COST_COLD_SLOAD;
    int256 immutable COST_COLD_SSTORE;
    int256 immutable COST_SSTORE_CHANGE_ORIGINAL_ZERO;
    int256 immutable COST_SSTORE_CHANGE_ORIGINAL_NONZERO;
    int256 immutable COST_SSTORE_CHANGE_NONORIGINAL;
    int256 immutable COST_INITIALIZE_ACCOUNT;
    int256 immutable REFUND_RESTORE_NONZERO_SLOT_TO_ZERO;
    int256 immutable REFUND_TEMP_ZERO_TO_NONZERO;
    int256 immutable REFUND_NONZERO_TO_ZERO;
    int256 immutable REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_WARM;
    int256 immutable REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_COLD;
    int256 immutable REFUND_RESTORE_ORIGINAL_NONZERO_WARM;
    int256 immutable REFUND_RESTORE_ORIGINAL_NONZERO_COLD;
    address private constant HEVM_ADDRESS =
        0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    Vm private constant vm = Vm(HEVM_ADDRESS);

    ///@notice Track the first time the target account is called.
    ///        When measuring tx-level gas, the initial call to the target
    ///        account should not incur any gas cost. Subsequent calls to the
    ///        target should incur a warm surcharge.
    bool seenTarget;

    ///@notice Struct to hold metadata about storage slot warmth and state for gas accounting purposes
    struct SlotStatus {
        ///@notice Whether the slot should be considered warm for the purposes of gas accounting
        bool isWarm;
        ///@notice Whether the slot was warmed by the test setup
        bool warmedBySetup;
        ///@notice Whether the slot should be considered warmed via access list
        bool warmedByAccessList;
        ///@notice Whether the slot has been processed, used to determine which value to use as evmOriginalValue
        bool touched;
        ///@notice The original value of the slot as considered by the EVM. Unless the test is running in a forked environment, this will always be zero.
        ///        Used for gas refund accounting.
        bytes32 evmOriginalValue;
        ///@notice What the manual accounting should consider the original value of the slot for refund accounting purposes.
        bytes32 testOriginalValue;
    }

    ///@notice Struct to hold metadata about account warmth for gas accounting purposes
    struct AccountStatus {
        ///@notice Whether the account should be considered warm for the purposes of gas accounting
        bool isWarm;
        ///@notice Whether the account was warmed by the test setup
        bool warmedBySetup;
        ///@notice Whether the account should be considered warmed via access list
        bool warmedByAccessList;
    }

    ///@notice Struct to hold the storage for this contract
    struct AccessAccountingStorage {
        mapping(address account => AccountStatus status) accountStatus;
        mapping(
            address account => mapping(bytes32 slot => SlotStatus slotStatus)
            ) slotStatus;
    }

    constructor(AccessCosts memory costs) {
        COST_BASE_ACCESS = costs.baseAccessCost;
        COST_COLD_ACCOUNT_ACCESS = costs.costColdAccountAccess;
        COST_COLD_SLOAD = costs.costColdSload;
        COST_COLD_SSTORE = costs.costColdSstore;
        COST_SSTORE_CHANGE_ORIGINAL_ZERO = costs.costSstoreChangeOriginalZero;
        COST_SSTORE_CHANGE_ORIGINAL_NONZERO =
            costs.costSstoreChangeOriginalNonZero;
        COST_SSTORE_CHANGE_NONORIGINAL = costs.costSstoreChangeNonOriginal;
        COST_INITIALIZE_ACCOUNT = costs.costInitializeAccount;
        REFUND_RESTORE_NONZERO_SLOT_TO_ZERO =
            costs.refundRestoreNonZeroSlotToZero;
        REFUND_TEMP_ZERO_TO_NONZERO = costs.refundTempZeroToNonZero;
        REFUND_NONZERO_TO_ZERO = costs.refundNonZeroToZero;
        REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_WARM =
            costs.refundRestoreTempNonZeroToZeroWarm;
        REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_COLD =
            costs.refundRestoreTempNonZeroToZeroCold;
        REFUND_RESTORE_ORIGINAL_NONZERO_WARM =
            costs.refundRestoreOriginalNonZeroWarm;
        REFUND_RESTORE_ORIGINAL_NONZERO_COLD =
            costs.refundRestoreOriginalNonZeroCold;
    }

    /**
     * @notice Make an account warm (by calling balance on it) and mark it internally as warm.
     *         Manually warmed accounts will not incur cold surcharges.
     * @param account The account to mark as warmed.
     * @return x The balance of the account, so the opcode is not optimized away.
     */
    function makeAndMarkWarm(address account) internal returns (uint256 x) {
        assembly {
            x := balance(account)
        }
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        slotMap.accountStatus[account] = AccountStatus({
            warmedBySetup: false,
            isWarm: true,
            warmedByAccessList: false
        });
    }

    /**
     * @notice Make an account and slot warm by calling vm.load and mark both internally as warm.
     * @param account The account to mark as warmed.
     * @param slot The slot to mark as warmed.
     * @return val The value of the warmed slot.
     */
    function makeAndMarkWarm(address account, bytes32 slot)
        internal
        returns (bytes32 val)
    {
        val = vm.load({target: account, slot: slot});

        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        slotMap.accountStatus[account] = AccountStatus({
            warmedBySetup: false,
            isWarm: true,
            warmedByAccessList: false
        });
        slotMap.slotStatus[account][slot] = SlotStatus({
            isWarm: true,
            warmedBySetup: false,
            warmedByAccessList: false,
            touched: true,
            evmOriginalValue: val,
            testOriginalValue: val
        });
    }

    /**
     * @notice Load an arbitrary slot from an account, and mark it as warm.
     * @dev Using vm.load marks both account and slot as warm, but will not
     *      show up in the state diff.
     *      TODO: handle loadAllocs as well
     * @param target The target account
     * @param slot The target slot to load
     * @return val The value of the slot
     */
    function safeLoad(address target, bytes32 slot)
        internal
        returns (bytes32 val)
    {
        return makeAndMarkWarm(target, slot);
    }

    /**
     * @notice Store a value in an arbitrary slot from an account, and mark it as warm.
     *         Note that this will update the testOriginalValue.
     * @param target The target account
     * @param slot The target slot to store
     * @param val The value to store
     * @return oldVal The old value of the slot
     */
    function safeStore(address target, bytes32 slot, bytes32 val)
        internal
        returns (bytes32 oldVal)
    {
        oldVal = makeAndMarkWarm(target, slot);
        vm.store({target: target, slot: slot, value: val});
        SlotStatus storage status =
            getAccessAccountingStorage().slotStatus[target][slot];
        status.testOriginalValue = val;
        return oldVal;
    }

    /**
     * @notice Process an access list, marking accounts and slots as warmed by the list.
     * @param accessList The access list to process.
     */
    function processAccessList(AccessListEntry[] memory accessList) internal {
        for (uint256 i; i < accessList.length; ++i) {
            processAccessListEntry(accessList[i]);
        }
    }

    /**
     * @notice Process an individual access list entry.
     * @param entry The access list entry to process.
     */
    function processAccessListEntry(AccessListEntry memory entry) internal {
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        address accessedAccount = entry.account;
        AccountStatus storage accountStatus =
            slotMap.accountStatus[accessedAccount];
        accountStatus.warmedByAccessList = true;
        bytes32[] memory storageAccesses = entry.storageKeys;
        for (uint256 i; i < storageAccesses.length; ++i) {
            SlotStatus storage slotStatus =
                slotMap.slotStatus[accessedAccount][storageAccesses[i]];
            slotStatus.warmedByAccessList = true;
        }
    }

    /**
     * @notice Get the storage struct for this contract
     */
    function getAccessAccountingStorage()
        internal
        pure
        returns (AccessAccountingStorage storage)
    {
        // TODO: support multiple forks by parameterizing this function
        uint256 forkId = 0;
        uint256 slot = ACCESS_ACCOUNTING_SLOT;
        AccessAccountingStorage storage accountingStorage;
        assembly {
            mstore(0x00, forkId)
            mstore(0x20, slot)
            accountingStorage.slot := keccak256(0x00, 0x40)
        }
        return accountingStorage;
    }

    /**
     * @notice Preprocess a list of account-level accesses, marking accounts and slots as warmed by setup.
     * @dev    Should be called after all test setup, and before the call to be metered.
     * @param accesses The account-level accesses to preprocess.
     */
    function preprocessAccountAccesses(Vm.AccountAccess[] memory accesses)
        public
        returns (Vm.AccountAccess[] memory)
    {
        for (uint256 i; i < accesses.length; ++i) {
            preprocessAccess(accesses[i]);
        }
        return accesses;
    }

    /**
     * @notice Preprocess an account-level access, marking accounts and slots as warmed by setup.
     * @param access The account-level access to preprocess.
     */
    function preprocessAccess(Vm.AccountAccess memory access) private {
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        address accessedAccount = access.account;
        AccountStatus storage accountStatus =
            slotMap.accountStatus[accessedAccount];
        if (!isPrecompile(access.account)) {
            accountStatus.warmedBySetup = true;
        }
        Vm.StorageAccess[] memory storageAccesses = access.storageAccesses;
        for (uint256 i; i < storageAccesses.length; ++i) {
            preprocessStorageAccess(storageAccesses[i]);
        }
    }

    /**
     * @notice Preprocess a storage access, marking slots as warmed by setup and
     *         noting current + original values.
     * @param access The storage access to preprocess.
     */
    function preprocessStorageAccess(Vm.StorageAccess memory access) private {
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        address accessedAccount = access.account;
        bytes32 accessedSlot = access.slot;
        SlotStatus storage slotStatus =
            slotMap.slotStatus[accessedAccount][accessedSlot];
        // don't do anything if access was reverted
        if (!access.reverted) {
            if (!slotStatus.touched && !slotStatus.warmedByAccessList) {
                slotStatus.warmedBySetup = true;
                slotStatus.touched = true;
                slotStatus.evmOriginalValue = access.previousValue;
            }
            slotStatus.testOriginalValue = access.newValue;
        }
    }

    /**
     * @notice Get the "original" value of a slot for the purposes of gas refund accounting, according to either the EVM or the test.
     * @param slotStatus The slot status struct for the slot.
     * @param access The storage access to process.
     * @param test Whether to return the value that the EVM considers the original value, or what the test context should consider the original value.
     * @return The "original" value of the slot.
     */
    function getOriginalSlotValue(
        SlotStatus storage slotStatus,
        Vm.StorageAccess memory access,
        bool test
    ) private returns (bytes32) {
        // if this is the first time the slot has been seen, assume the access.previousValue is also its original value.
        if (!slotStatus.touched) {
            slotStatus.evmOriginalValue = access.previousValue;
            slotStatus.testOriginalValue = access.previousValue;
            slotStatus.touched = true;
        }
        return
            (test) ? slotStatus.testOriginalValue : slotStatus.evmOriginalValue;
    }

    /**
     * @notice Process the list of account-level accesses incurred during a metered call.
     * @param target If doing tx-level metering, the target account of the tx. The first access of this account will not incur either a cold or warm surcharge. Subsequent accesses will incur a warm surcharge.
     * @param accesses The account-level accesses to process as a result of the call.
     * @return measurements The gas measurements for the call.
     */
    function processAccountAccesses(
        address target,
        Vm.AccountAccess[] memory accesses
    ) public returns (GasMeasurements memory measurements) {
        seenTarget = false;
        int256 evmGas;
        int256 adjustedGas;
        int256 evmRefund;
        int256 adjustedRefund;
        for (uint256 i; i < accesses.length; ++i) {
            (
                int256 evmGas_,
                int256 adjustedGas_,
                int256 evmRefund_,
                int256 adjustedRefund_
            ) = processAccountAccess(target, accesses[i]);
            evmGas += evmGas_;
            adjustedGas += adjustedGas_;
            evmRefund += evmRefund_;
            adjustedRefund += adjustedRefund_;
        }
        return GasMeasurements(evmGas, adjustedGas, evmRefund, adjustedRefund);
    }

    /**
     * @notice Process the account-level access, including all storage accesses.
     *         If an account was warmed by set-up, the cold surcharge will added to
     *         extraGas only the first time the account is accessed.
     *         If the access callframe did not revert, the account will be marked as warmed.
     *         Actual and adjusted gas and refunds are calculate separately because of EVM behavior around refunds.
     *         As of London hard fork, the EVM limits refunds to 1/5 tx cost, and only gives refunds for SSTOREs.
     * @param access The account-level access to process, including all storage accesses.
     */
    function processAccountAccess(
        address target,
        Vm.AccountAccess memory access
    )
        private
        returns (
            int256 evmGas,
            int256 adjustedGas,
            int256 evmRefund,
            int256 adjustedRefund
        )
    {
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        address accessedAccount = access.account;
        AccountStatus storage accountStatus =
            slotMap.accountStatus[accessedAccount];

        if (access.account == target && !seenTarget) {
            seenTarget = true;
            // if this is the first time the target account is accessed,
            // do not charge any gas, since that will be accounted for by the
            // tx-level overhead.
            // todo: make this configurable?
            adjustedGas = 0;
            // however, assume the evm charges standard gas for the call;
            // the difference will be accounted for by the burned makeup gas.
            evmGas = COST_BASE_ACCESS;
            evmGas += (accountStatus.warmedBySetup)
                ? int256(0)
                : COST_COLD_ACCOUNT_ACCESS;
            evmGas += (access.value > 0 && !access.initialized)
                ? COST_INITIALIZE_ACCOUNT
                : int256(0);
            // warm up target account
            accountStatus.warmedBySetup = false;
            accountStatus.isWarm = true;
            accountStatus.warmedByAccessList = false;
        } else {
            evmGas = adjustedGas = COST_BASE_ACCESS;

            // call and selfdestruct must pay extra gas for uninitialized accounts
            if (
                (
                    access.kind == VmSafe.AccountAccessKind.Call
                        || access.kind == VmSafe.AccountAccessKind.SelfDestruct
                )
            ) {
                // struct already accounts for whether or not account is initialized, including due to reverts
                if (access.value > 0 && !access.initialized) {
                    adjustedGas += COST_INITIALIZE_ACCOUNT; // COST_UNINITIALIZED_ACCOUNT_SEND_VALUE
                    evmGas += COST_INITIALIZE_ACCOUNT;
                }
            }

            if (!isPrecompile(access.account)) {
                if ((accountStatus.warmedBySetup || !accountStatus.isWarm)) {
                    // create and resume do not pay extra gas for cold accounts
                    if (
                        !(
                            access.kind == VmSafe.AccountAccessKind.Create
                                || access.kind == VmSafe.AccountAccessKind.Resume
                        )
                    ) {
                        adjustedGas += (accountStatus.warmedByAccessList)
                            ? int256(0)
                            : COST_COLD_ACCOUNT_ACCESS;
                        // only add cold surcharge to evmGas if the account was not warmed by set-up
                        evmGas += (accountStatus.warmedBySetup)
                            ? int256(0)
                            : COST_COLD_ACCOUNT_ACCESS;
                    }
                    // If this is the first time the account is accessed, and the
                    // callframe did not revert, or if the account was the target of a
                    // CREATE, mark it as warmed and reset needsWarmAdjusment.
                    // TODO: technically, only a CREATE from a non-reverted frame should warm the account
                    // eg, if a CREATE reverts _within_ a reverting frame, the account should not be warmed (I think)
                    if (
                        !access.reverted
                            || access.kind == VmSafe.AccountAccessKind.Create
                    ) {
                        accountStatus.isWarm = true;
                        accountStatus.warmedBySetup = false;
                        accountStatus.warmedByAccessList = false;
                    }
                } else if (
                    accountStatus.warmedByAccessList && !access.reverted
                        && !(
                            access.kind == VmSafe.AccountAccessKind.Create
                                || access.kind == VmSafe.AccountAccessKind.Resume
                        )
                ) {
                    // if the account was warmed by the access list, but not by set-up,
                    // charge the cold surcharge to the EVM, but not to the adjusted gas
                    evmGas += (accountStatus.warmedBySetup)
                        ? int256(0)
                        : COST_COLD_ACCOUNT_ACCESS;
                    accountStatus.isWarm = true;
                    accountStatus.warmedByAccessList = false;
                    accountStatus.warmedBySetup = false;
                }
            }
        }

        Vm.StorageAccess[] memory storageAccesses = access.storageAccesses;
        for (uint256 i; i < storageAccesses.length; ++i) {
            (
                int256 slotEvmGas,
                int256 slotAdjustedGas,
                int256 slotEvmRefund,
                int256 slotAdjustedRefund
            ) = processStorageAccess(storageAccesses[i]);
            evmGas += slotEvmGas;
            adjustedGas += slotAdjustedGas;
            evmRefund += slotEvmRefund;
            adjustedRefund += slotAdjustedRefund;
        }
        return (evmGas, adjustedGas, evmRefund, adjustedRefund);
    }

    /**
     *
     * @param access The storage access to process.
     * @return evmGas The amount of gas actually charged by the EVM for this access.
     * @return adjustedGas The amount of gas that would have been charged by the EVM if the slot were cold and started with its correct value.
     * @return evmRefund The amount of refund actually given by the EVM for this access.
     * @return adjustedRefund The amount of refund that would have been given by the EVM if the slot were cold and started with its correct value.
     */
    function processStorageAccess(Vm.StorageAccess memory access)
        private
        returns (
            int256 evmGas,
            int256 adjustedGas,
            int256 evmRefund,
            int256 adjustedRefund
        )
    {
        AccessAccountingStorage storage slotMap = getAccessAccountingStorage();
        address accessedAccount = access.account;
        bytes32 accessedSlot = access.slot;
        SlotStatus storage slotStatus =
            slotMap.slotStatus[accessedAccount][accessedSlot];
        // if doing an SLOAD, just account for the cold surcharge, and do nothing with refunds
        if (!access.isWrite) {
            evmGas = adjustedGas = COST_BASE_ACCESS;
            if (slotStatus.warmedBySetup || !slotStatus.isWarm) {
                adjustedGas += (slotStatus.warmedByAccessList)
                    ? int256(0)
                    : COST_COLD_SLOAD;
                // only add cold surcharge to evmGas if the slot was not warmed by set-up
                evmGas +=
                    (slotStatus.warmedBySetup) ? int256(0) : COST_COLD_SLOAD;
                if (!access.reverted) {
                    slotStatus.isWarm = true;
                    slotStatus.warmedBySetup = false;
                    slotStatus.warmedByAccessList = false;
                }
            }
        } else {
            // for SSTOREs, calculate both the gas and refund for both the EVM state and the idealized test state

            // use helper to get original values, as they may not have been recorded during preprocessing of test setup
            // TODO: support pre-loaded state with forks/vm.loadAllocs etc
            bytes32 evmOriginalValue = getOriginalSlotValue({
                slotStatus: slotStatus,
                access: access,
                test: false
            });
            bytes32 testOriginalValue = getOriginalSlotValue({
                slotStatus: slotStatus,
                access: access,
                test: true
            });
            bool evmWarm = slotStatus.isWarm || slotStatus.warmedBySetup;
            bytes32 currentValue = access.previousValue;
            bytes32 newValue = access.newValue;
            (evmGas, evmRefund) = calcSstoreCost(
                evmWarm, evmOriginalValue, currentValue, newValue
            );
            (adjustedGas, adjustedRefund) = calcSstoreCost(
                slotStatus.isWarm || slotStatus.warmedByAccessList,
                testOriginalValue,
                currentValue,
                newValue
            );
            if (!access.reverted) {
                slotStatus.isWarm = true;
                slotStatus.warmedBySetup = false;
                slotStatus.warmedByAccessList = false;
            }
        }
        return (evmGas, adjustedGas, evmRefund, adjustedRefund);
    }

    /**
     * @notice Calculate the gas used by an SSTORE as well as any incurred refunds.
     * @param warm Whether the slot is warm.
     * @param originalValue The original (pre-tx) value of the slot.
     * @param currentValue The current value of the slot.
     * @param newValue The new value of the slot.
     */
    function calcSstoreCost(
        bool warm,
        bytes32 originalValue,
        bytes32 currentValue,
        bytes32 newValue
    ) private view returns (int256 baseDynamicGas, int256 gasRefund) {
        return (
            calcSstoreBaseDynamicGas(
                warm, originalValue, currentValue, newValue
                ),
            calcSstoreGasRefund(warm, originalValue, currentValue, newValue)
        );
    }

    /**
     * @notice Calculate the base dynamic gas for an SSTORE. Virtual to allow overriding for different networks and hard forks.
     * @param warm Whether the slot is warm.
     * @param originalValue The original (pre-tx) value of the slot.
     * @param currentValue The current value of the slot.
     * @param newValue The new value of the slot.
     */
    function calcSstoreBaseDynamicGas(
        bool warm,
        bytes32 originalValue,
        bytes32 currentValue,
        bytes32 newValue
    ) internal view virtual returns (int256 baseDynamicGas) {
        if (newValue == currentValue) {
            if (warm) {
                baseDynamicGas = COST_BASE_ACCESS;
            } else {
                baseDynamicGas = COST_BASE_ACCESS;
            }
        } else if (currentValue == originalValue) {
            if (originalValue == 0) {
                baseDynamicGas = COST_SSTORE_CHANGE_ORIGINAL_ZERO;
            } else {
                baseDynamicGas = COST_SSTORE_CHANGE_ORIGINAL_NONZERO;
            }
        } else {
            baseDynamicGas = COST_SSTORE_CHANGE_NONORIGINAL;
        }
        baseDynamicGas += (warm) ? int256(0) : int256(COST_COLD_SSTORE);
    }

    /**
     * @notice Calculate the gas refund for an SSTORE. Virtual to allow overriding for different networks and hard forks.
     * @param warm Whether the slot is warm.
     * @param originalValue The original (pre-tx) value of the slot.
     * @param currentValue The current value of the slot.
     * @param newValue The new value of the slot.
     */
    function calcSstoreGasRefund(
        bool warm,
        bytes32 originalValue,
        bytes32 currentValue,
        bytes32 newValue
    ) internal view virtual returns (int256 gasRefund) {
        if (newValue != currentValue) {
            if (currentValue == originalValue) {
                if (originalValue != 0 && newValue == 0) {
                    gasRefund += REFUND_RESTORE_NONZERO_SLOT_TO_ZERO;
                }
            } else if (originalValue != 0) {
                if (currentValue == 0) {
                    gasRefund -= REFUND_TEMP_ZERO_TO_NONZERO;
                } else if (newValue == 0) {
                    gasRefund += REFUND_NONZERO_TO_ZERO;
                }
            }
        }
        if (newValue == originalValue) {
            if (originalValue == 0) {
                if (warm) {
                    gasRefund += REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_WARM;
                } else {
                    gasRefund += REFUND_RESTORE_TEMP_NONZERO_TO_ZERO_COLD;
                }
            } else {
                if (warm) {
                    gasRefund += REFUND_RESTORE_ORIGINAL_NONZERO_WARM;
                } else {
                    gasRefund += REFUND_RESTORE_ORIGINAL_NONZERO_COLD;
                }
            }
        }
    }

    /**
     * @notice Check if an account is a precompile. Override with different logic depending on network and hard fork.
     * @param account The account to check.
     */
    function isPrecompile(address account)
        internal
        view
        virtual
        returns (bool)
    {
        return (account < address(10) && account > address(0))
            || account == HEVM_ADDRESS;
    }
}
