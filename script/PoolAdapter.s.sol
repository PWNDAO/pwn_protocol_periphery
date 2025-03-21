// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Script, console2 } from "forge-std/Script.sol";

import { GnosisSafeLike, GnosisSafeUtils } from "pwn/../script/lib/GnosisSafeUtils.sol";
import { TimelockController, TimelockUtils } from "pwn/../script/lib/TimelockUtils.sol";

import {
    Deployments,
    PWNConfig,
    IPWNDeployer
} from "pwn/Deployments.sol";

import { AaveAdapter } from "src/pool-adapter/AaveAdapter.sol";
import { CompoundAdapter } from "src/pool-adapter/CompoundAdapter.sol";
import { ERC4626Adapter } from "src/pool-adapter/ERC4626Adapter.sol";


library PWNDeployerSalt {

    bytes32 internal constant AAVE = keccak256("PWN_AAVE");
    bytes32 internal constant COMPOUND = keccak256("PWN_COMPOUND");
    bytes32 internal constant ERC4626_VAULT = keccak256("PWN_ERC4626_VAULT");

}

contract Deploy is Deployments, Script {
    using GnosisSafeUtils for GnosisSafeLike;

    constructor() {
        deploymentsSubpath = "/lib/pwn_protocol";
    }

    function _protocolNotDeployedOnSelectedChain() internal pure override {
        revert("PWN: selected chain is not set in deployments/latest.json");
    }

    function _deploy(
        bytes32 salt,
        bytes memory bytecode
    ) internal returns (address) {
        bool success = GnosisSafeLike(deployment.deployerSafe).execTransaction({
            to: address(deployment.deployer),
            data: abi.encodeWithSelector(
                IPWNDeployer.deploy.selector, salt, bytecode
            )
        });
        require(success, "Deploy failed");
        return deployment.deployer.computeAddress(salt, keccak256(bytecode));
    }


/*
forge script script/PoolAdapter.s.sol:Deploy \
--sig "deployPoolAdapters()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--verify --etherscan-api-key $ETHERSCAN_API_KEY \
--broadcast --slow
*/
    /// @dev Expecting to have deployer, deployerSafe & hub
    /// addresses set in the `deployments/latest.json`.
    function deployPoolAdapters() public {
        _loadDeployedAddresses();

        require(address(deployment.deployer) != address(0), "Deployer not set");
        require(deployment.deployerSafe != address(0), "Deployer safe not set");
        require(address(deployment.hub) != address(0), "Hub not set");

        vm.startBroadcast();

        address aaveAdapter = _deploy(
            PWNDeployerSalt.AAVE,
            abi.encodePacked(
                type(AaveAdapter).creationCode, abi.encode(address(deployment.hub))
            )
        );
        console2.log("AaveAdapter:", aaveAdapter);

        address compoundAdapter = _deploy(
            PWNDeployerSalt.COMPOUND,
            abi.encodePacked(
                type(CompoundAdapter).creationCode, abi.encode(deployment.hub)
            )
        );
        console2.log("CompoundAdapter:", compoundAdapter);

        address erc4626VaultAdapter = _deploy(
            PWNDeployerSalt.ERC4626_VAULT,
            abi.encodePacked(
                type(ERC4626Adapter).creationCode, abi.encode(deployment.hub)
            )
        );
        console2.log("ERC4626Adapter:", erc4626VaultAdapter);

        vm.stopBroadcast();
    }

}


contract Setup is Deployments, Script {
    using GnosisSafeUtils for GnosisSafeLike;
    using TimelockUtils for TimelockController;

    constructor() {
        deploymentsSubpath = "/lib/pwn_protocol";
    }

    function _protocolNotDeployedOnSelectedChain() internal pure override {
        revert("PWN: selected chain is not set in deployments/latest.json");
    }


/*
forge script script/PoolAdapter.s.sol:Setup \
--sig "registerAdapters()" \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--with-gas-price $(cast --to-wei 15 gwei) \
--broadcast --slow
*/
    /// @dev Expecting to have daoSafe, protocolTimelock & config
    /// addresses set in the `deployments/latest.json`.
    function registerAdapters() external {
        _loadDeployedAddresses();

        require(deployment.daoSafe != address(0), "DAO Safe not set");
        require(deployment.protocolTimelock != address(0), "Protocol timelock not set");
        require(address(deployment.config) != address(0), "Config not set");

        vm.startBroadcast();

        address[] memory pools = new address[](3);
        pools[0] = 0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e; // Compound Sepolia USDC
        pools[1] = 0x2943ac1216979aD8dB76D9147F64E61adc126e96; // Compound Sepolia WETH
        pools[2] = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951; // Aave Sepolia
        address[] memory adapters = new address[](3);
        adapters[0] = 0x037eC401a14b6cF24E7f69e51D29047f5d3b1592; // Compound
        adapters[1] = 0x037eC401a14b6cF24E7f69e51D29047f5d3b1592; // Compound
        adapters[2] = 0x1bD2794d545B488d5Cf848912af38b5283d101b7; // Aave

        for (uint256 i; i < pools.length; ++i) {
            TimelockController(payable(deployment.protocolTimelock)).scheduleAndExecute(
                GnosisSafeLike(deployment.daoSafe),
                address(deployment.config),
                abi.encodeWithSignature("registerPoolAdapter(address,address)", pools[i], adapters[i])
            );
            console2.log("Register pool adapter tx succeeded", pools[i], adapters[i]);
        }

        vm.stopBroadcast();
    }

}
