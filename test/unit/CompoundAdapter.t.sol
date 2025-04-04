// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    PoolZeroAddress,
    OwnerZeroAddress,
    AssetZeroAddress,
    AmountZero
} from "src/pool-adapter/utils/checkInputs.sol";
import {
    CompoundAdapter,
    ICometLike,
    PWNHubTags,
    AddressMissingHubTag
} from "src/pool-adapter/CompoundAdapter.sol";


contract CompoundAdapterTest is Test {

    address hub;
    address activeLoan;
    address pool;
    address asset;
    address owner;
    uint256 amount;

    CompoundAdapter adapter;

    function setUp() public virtual {
        hub = makeAddr("hub");
        activeLoan = makeAddr("activeLoan");
        pool = makeAddr("pool");
        asset = makeAddr("asset");
        owner = makeAddr("owner");
        amount = 100;

        adapter = new CompoundAdapter(hub);

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", activeLoan, PWNHubTags.ACTIVE_LOAN),
            abi.encode(true)
        );
        vm.mockCall(pool, abi.encodeWithSelector(ICometLike.supplyFrom.selector), abi.encode(""));
        vm.mockCall(pool, abi.encodeWithSelector(ICometLike.withdrawFrom.selector), abi.encode(""));
        vm.mockCall(asset, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
        vm.mockCall(asset, abi.encodeWithSignature("allowance(address,address)"), abi.encode(0));
    }

}

contract CompoundAdapter_Constructor_Test is CompoundAdapterTest {

    function test_shouldFail_whenHubZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(CompoundAdapter.HubZeroAddress.selector));
        new CompoundAdapter(address(0));
    }

}

contract CompoundAdapter_Withdraw_Test is CompoundAdapterTest {

    function test_shouldFail_whenPoolZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(PoolZeroAddress.selector));
        adapter.withdraw(address(0), owner, asset, amount);
    }

    function test_shouldFail_whenOwnerZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(OwnerZeroAddress.selector));
        adapter.withdraw(pool, address(0), asset, amount);
    }

    function test_shouldFail_whenAssetZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(AssetZeroAddress.selector));
        adapter.withdraw(pool, owner, address(0), amount);
    }

    function test_shouldFail_whenAmountZero() external {
        vm.expectRevert(abi.encodeWithSelector(AmountZero.selector));
        adapter.withdraw(pool, owner, asset, 0);
    }

    function testFuzz_shouldFail_whenCallerNotActiveLoan(address caller) external {
        vm.assume(caller != activeLoan);

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, caller, PWNHubTags.ACTIVE_LOAN));
        vm.prank(caller);
        adapter.withdraw(pool, owner, asset, amount);
    }

    function testFuzz_shouldWithdrawFromCompound(address _owner, address _asset, uint256 _amount) external {
        vm.assume(_owner != address(0));
        vm.assume(_asset != address(0));
        vm.assume(_amount > 0);

        vm.expectCall(
            pool, abi.encodeWithSelector(ICometLike.withdrawFrom.selector, _owner, _owner, _asset, _amount)
        );

        vm.prank(activeLoan);
        adapter.withdraw(pool, _owner, _asset, _amount);
    }

}

contract CompoundAdapter_Supply_Test is CompoundAdapterTest {

    function test_shouldFail_whenPoolZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(PoolZeroAddress.selector));
        adapter.supply(address(0), owner, asset, amount);
    }

    function test_shouldFail_whenOwnerZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(OwnerZeroAddress.selector));
        adapter.supply(pool, address(0), asset, amount);
    }

    function test_shouldFail_whenAssetZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(AssetZeroAddress.selector));
        adapter.supply(pool, owner, address(0), amount);
    }

    function test_shouldFail_whenAmountZero() external {
        vm.expectRevert(abi.encodeWithSelector(AmountZero.selector));
        adapter.supply(pool, owner, asset, 0);
    }

    function testFuzz_shouldApproveCompound(uint256 _amount) external {
        vm.assume(_amount > 0);

        vm.expectCall(asset, abi.encodeWithSignature("approve(address,uint256)", pool, _amount));

        adapter.supply(pool, owner, asset, _amount);
    }

    function testFuzz_shouldDepositToCompound(address _owner, uint256 _amount) external {
        vm.assume(_owner != address(0));
        vm.assume(_amount > 0);

        vm.expectCall(pool, abi.encodeWithSelector(ICometLike.supplyFrom.selector, address(adapter), _owner, asset, _amount));

        adapter.supply(pool, _owner, asset, _amount);
    }

}
