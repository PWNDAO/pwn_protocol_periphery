// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    AaveAdapter,
    IAavePoolLike,
    PWNHubTags,
    AddressMissingHubTag
} from "src/pool-adapter/AaveAdapter.sol";


contract AaveAdapterTest is Test {

    address hub;
    address activeLoan;
    address pool;
    address asset;
    address aToken;
    address owner;
    uint256 amount;

    AaveAdapter adapter;

    function setUp() public virtual {
        hub = makeAddr("hub");
        activeLoan = makeAddr("activeLoan");
        pool = makeAddr("pool");
        asset = makeAddr("asset");
        aToken = makeAddr("aToken");
        owner = makeAddr("owner");
        amount = 100;

        adapter = new AaveAdapter(hub);

        vm.mockCall(hub, abi.encodeWithSignature("hasTag(address,bytes32)"), abi.encode(false));
        vm.mockCall(
            hub,
            abi.encodeWithSignature("hasTag(address,bytes32)", activeLoan, PWNHubTags.ACTIVE_LOAN),
            abi.encode(true)
        );
        vm.mockCall(pool, abi.encodeWithSelector(IAavePoolLike.supply.selector), abi.encode(""));
        vm.mockCall(pool, abi.encodeWithSelector(IAavePoolLike.withdraw.selector), abi.encode(0));
        _mockReserveData(pool, asset, aToken);
        _mockUserAccountData(pool, owner, adapter.DEFAULT_MIN_HEALTH_FACTOR());
        vm.mockCall(asset, abi.encodeWithSignature("approve(address,uint256)"), abi.encode(true));
        vm.mockCall(asset, abi.encodeWithSignature("allowance(address,address)"), abi.encode(0));
        vm.mockCall(aToken, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true));
    }

    function _mockReserveData(address _pool, address _asset, address _aTokenAddress) internal {
        IAavePoolLike.ReserveData memory reserveData;
        reserveData.aTokenAddress = _aTokenAddress;
        vm.mockCall(
            _pool,
            abi.encodeWithSelector(IAavePoolLike.getReserveData.selector, _asset),
            abi.encode(reserveData)
        );
    }

    function _mockUserAccountData(address _pool, address _owner, uint256 _healthFactor) internal {
        vm.mockCall(
            _pool,
            abi.encodeWithSelector(IAavePoolLike.getUserAccountData.selector, _owner),
            abi.encode(0, 0, 0, 0, 0, _healthFactor)
        );
    }

}

contract AaveAdapter_Withdraw_Test is AaveAdapterTest {

    function testFuzz_shouldFail_whenCallerNotActiveLoan(address caller) external {
        vm.assume(caller != activeLoan);

        vm.expectRevert(abi.encodeWithSelector(AddressMissingHubTag.selector, caller, PWNHubTags.ACTIVE_LOAN));
        vm.prank(caller);
        adapter.withdraw(pool, owner, asset, amount);
    }

    function testFuzz_shouldTransferATokensToAdapter(address _owner, uint256 _amount) external {
        _mockUserAccountData(pool, _owner, adapter.DEFAULT_MIN_HEALTH_FACTOR());

        vm.expectCall(
            aToken, abi.encodeWithSignature("transferFrom(address,address,uint256)", _owner, address(adapter), _amount)
        );

        vm.prank(activeLoan);
        adapter.withdraw(pool, _owner, asset, _amount);
    }

    function testFuzz_shouldFail_whenOwnerHealthFactorBelowMin_whenSet(uint256 _healthFactor) external {
        uint256 minHealthFactor = 2e18;
        _healthFactor = bound(_healthFactor, 0, minHealthFactor - 1);
        _mockUserAccountData(pool, owner, _healthFactor);

        vm.prank(owner);
        adapter.setMinHealthFactor(minHealthFactor);

        vm.expectRevert(abi.encodeWithSelector(AaveAdapter.HealthFactorBelowMin.selector, minHealthFactor, _healthFactor));
        vm.prank(activeLoan);
        adapter.withdraw(pool, owner, asset, amount);
    }

    function testFuzz_shouldFail_whenOwnerHealthFactorBelowDefautlMin_whenNotSet(uint256 _healthFactor) external {
        uint256 minHealthFactor = adapter.DEFAULT_MIN_HEALTH_FACTOR();
        _healthFactor = bound(_healthFactor, 0, minHealthFactor - 1);
        _mockUserAccountData(pool, owner, _healthFactor);

        vm.expectRevert(abi.encodeWithSelector(AaveAdapter.HealthFactorBelowMin.selector, minHealthFactor, _healthFactor));
        vm.prank(activeLoan);
        adapter.withdraw(pool, owner, asset, amount);
    }

    function testFuzz_shouldWithdrawFromPool(address _owner, address _asset, uint256 _amount) external {
        _mockReserveData(pool, _asset, aToken);
        _mockUserAccountData(pool, _owner, adapter.DEFAULT_MIN_HEALTH_FACTOR());

        vm.expectCall(
            pool, abi.encodeWithSelector(IAavePoolLike.withdraw.selector, _asset, _amount, _owner)
        );

        vm.prank(activeLoan);
        adapter.withdraw(pool, _owner, _asset, _amount);
    }

}

contract AaveAdapter_Supply_Test is AaveAdapterTest {

    function testFuzz_shouldApprovePool(uint256 _amount) external {
        vm.expectCall(asset, abi.encodeWithSignature("approve(address,uint256)", pool, _amount));

        adapter.supply(pool, owner, asset, _amount);
    }

    function testFuzz_shouldDepositToPool(address _owner, uint256 _amount) external {
        vm.expectCall(pool, abi.encodeWithSelector(IAavePoolLike.supply.selector, asset, _amount, _owner, 0));

        adapter.supply(pool, _owner, asset, _amount);
    }

}

contract AaveAdapter_SetMinHealthFactor_Test is AaveAdapterTest {

    function testFuzz_shouldFail_whenNewHealthFactorLessThanOne(uint256 newHealthFactor) external {
        newHealthFactor = bound(newHealthFactor, 0, 1e18 - 1);

        vm.expectRevert(abi.encodeWithSelector(AaveAdapter.InvalidMinHealthFactor.selector, newHealthFactor));
        vm.prank(owner);
        adapter.setMinHealthFactor(newHealthFactor);
    }

    function testFuzz_shouldUpdateMinHealthFactor(uint256 newHealthFactor) external {
        newHealthFactor = bound(newHealthFactor, 1e18, type(uint256).max);

        vm.prank(owner);
        adapter.setMinHealthFactor(newHealthFactor);

        assertEq(adapter.minHealthFactor(owner), newHealthFactor);
    }

}
