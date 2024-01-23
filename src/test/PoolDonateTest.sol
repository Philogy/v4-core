// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {Test} from "forge-std/Test.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";

contract PoolDonateTest is PoolTestBase, Test {
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    enum DonateType {
        Single,
        Multi
    }

    struct SingleDonateData {
        uint256 amount0;
        uint256 amount1;
    }

    struct SingleOrMultiDonate {
        DonateType donateType;
        address sender;
        PoolKey key;
        bytes hookData;
        bytes variantUniqueData;
    }

    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.lock(
                address(this),
                abi.encode(
                    SingleOrMultiDonate(
                        DonateType.Single, msg.sender, key, hookData, abi.encode(SingleDonateData(amount0, amount1))
                    )
                )
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function donateMulti(PoolKey calldata key, IPoolManager.MultiDonateParams calldata params, bytes calldata hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.lock(
                address(this),
                abi.encode(SingleOrMultiDonate(DonateType.Single, msg.sender, key, hookData, abi.encode(params)))
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(address, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        SingleOrMultiDonate memory data = abi.decode(rawData, (SingleOrMultiDonate));

        BalanceDelta delta;
        PoolKey memory key = data.key;
        address sender = data.sender;
        if (data.donateType == DonateType.Single) {
            SingleDonateData memory singleData = abi.decode(data.variantUniqueData, (SingleDonateData));
            delta = manager.donate(key, singleData.amount0, singleData.amount1, data.hookData);
        } else if (data.donateType == DonateType.Multi) {
            IPoolManager.MultiDonateParams memory params =
                abi.decode(data.variantUniqueData, (IPoolManager.MultiDonateParams));
            delta = manager.donate(key, params, data.hookData);
        }

        if (delta.amount0() > 0) {
            if (key.currency0.isNative()) {
                manager.settle{value: uint128(delta.amount0())}(key.currency0);
            } else {
                IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(
                    sender, address(manager), uint128(delta.amount0())
                );
                manager.settle(key.currency0);
            }
        }
        if (delta.amount1() > 0) {
            if (key.currency1.isNative()) {
                manager.settle{value: uint128(delta.amount1())}(key.currency1);
            } else {
                IERC20Minimal(Currency.unwrap(key.currency1)).transferFrom(
                    sender, address(manager), uint128(delta.amount1())
                );
                manager.settle(key.currency1);
            }
        }

        return abi.encode(delta);
    }
}
