// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    ERC4626Adapter,
    IERC4626Like,
    PWNHubTags,
    AddressMissingHubTag
} from "src/pool-adapter/ERC4626Adapter.sol";


contract ERC4626AdapterTest is Test {

    address hub;
    address activeLoan;
    address pool;
    address asset;
    address owner;
    uint256 amount;

    ERC4626Adapter adapter;

    function setUp() public virtual {
        hub = makeAddr("hub");
        activeLoan = makeAddr("activeLoan");
        pool = makeAddr("pool");
        asset = makeAddr("asset");
        owner = makeAddr("owner");
        amount = 100;

        adapter = new ERC4626Adapter(hub);

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", activeLoan, PWNHubTags.ACTIVE_LOAN),
            abi.encode(true)
        );
        vm.mockCall(pool, abi.encodeWithSelector(IERC4626Like.asset.selector), abi.encode(asset));
        vm.mockCall(pool, abi.encodeWithSelector(IERC4626Like.withdraw.selector), abi.encode(amount));
        vm.mockCall(pool, abi.encodeWithSelector(IERC4626Like.deposit.selector), abi.encode(amount));
        vm.mockCall(asset, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
        vm.mockCall(asset, abi.encodeWithSignature("allowance(address,address)"), abi.encode(0));
    }

}

contract ERC4626Adapter_Withdraw_Test is ERC4626AdapterTest {

    function testFuzz_shouldFail_whenCallerNotActiveLoan(address caller) external {
        vm.assume(caller != activeLoan);

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, caller, PWNHubTags.ACTIVE_LOAN));
        vm.prank(caller);
        adapter.withdraw(pool, owner, asset, amount);
    }

    function testFuzz_shouldFail_whenVaultAssetNotWithdrawAsset(address invalidAsset) external {
        vm.assume(invalidAsset != asset);

        vm.expectRevert(abi.encodeWithSelector(ERC4626Adapter.InvalidVaultAsset.selector, invalidAsset, asset));
        vm.prank(activeLoan);
        adapter.withdraw(pool, owner, invalidAsset, amount);
    }

    function testFuzz_shouldWithdrawFromVault(address _owner, uint256 _amount) external {
        vm.mockCall(pool, abi.encodeWithSelector(IERC4626Like.withdraw.selector), abi.encode(_amount));

        vm.expectCall(
            pool, abi.encodeWithSelector(IERC4626Like.withdraw.selector, _amount, _owner, _owner)
        );

        vm.prank(activeLoan);
        adapter.withdraw(pool, _owner, asset, _amount);
    }

}

contract ERC4626Adapter_Supply_Test is ERC4626AdapterTest {

    function testFuzz_shouldFail_whenVaultAssetNotSupplyAsset(address invalidAsset) external {
        vm.assume(invalidAsset != asset);

        vm.expectRevert(abi.encodeWithSelector(ERC4626Adapter.InvalidVaultAsset.selector, invalidAsset, asset));
        adapter.supply(pool, owner, invalidAsset, amount);
    }

    function testFuzz_shouldApproveVault(uint256 _amount) external {
        vm.expectCall(asset, abi.encodeWithSignature("approve(address,uint256)", pool, _amount));

        adapter.supply(pool, owner, asset, _amount);
    }

    function testFuzz_shouldDepositToVault(address _owner, uint256 _amount) external {
        vm.mockCall(pool, abi.encodeWithSelector(IERC4626Like.deposit.selector), abi.encode(_amount));

        vm.expectCall(pool, abi.encodeWithSelector(IERC4626Like.deposit.selector, _amount, _owner));

        adapter.supply(pool, _owner, asset, _amount);
    }

}
