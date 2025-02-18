// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

import {
    WorldIdAcceptorController,
    IWorldID,
    IPWNAcceptorController
} from "src/acceptor-controller/WorldIdAcceptorController.sol";

import { WorldIdAcceptorControllerHarness } from "../harness/WorldIdAcceptorControllerHarness.sol";


abstract contract WorldIdAcceptorControllerTest is Test {

    address acceptor = makeAddr("acceptor");
    address worldId = makeAddr("worldId");
    uint256 externalNullifier;
    WorldIdAcceptorControllerHarness controller;

    function setUp() public virtual {
        controller = new WorldIdAcceptorControllerHarness(IWorldID(worldId), "app_id", "action_id");
        externalNullifier = controller.exposed_hashToField(abi.encodePacked(
            controller.exposed_hashToField(abi.encodePacked("app_id")), "action_id"
        ));

        vm.etch(worldId, "code");
    }

}

contract WorldIdAcceptorController_CheckAcceptor_Test is WorldIdAcceptorControllerTest {

    WorldIdAcceptorController.AcceptorData acceptorData;

    function setUp() override public virtual {
        super.setUp();

        acceptorData = WorldIdAcceptorController.AcceptorData({
            root: 1,
            nullifierHash: 2,
            proof: [uint256(1), 2, 3, 4, 5, 6, 7, 8]
        });
    }

    function test_shouldFail_whenProposerDataNotEmpty() external {
        vm.expectRevert(WorldIdAcceptorController.NonEmptyProposerData.selector);
        controller.checkAcceptor(acceptor, abi.encodePacked("proposerData"), abi.encodePacked("acceptorData"));
    }

    function test_shouldFail_whenInvalidAcceptorData() external {
        vm.expectRevert();
        controller.checkAcceptor(acceptor, "", abi.encodePacked("acceptorData"));
    }

    function test_shouldFail_whenVerifyProofFails() external {
        vm.mockCallRevert(
            worldId,
            abi.encodeWithSelector(IWorldID.verifyProof.selector),
            "no good"
        );

        vm.expectRevert("no good");
        controller.checkAcceptor(acceptor, "", abi.encode(acceptorData));
    }

    function test_shouldCallVerifyProof() external {
        uint256 signalHash = controller.exposed_hashToField(abi.encodePacked(acceptor));

        vm.expectCall(
            worldId,
            abi.encodeWithSelector(
                IWorldID.verifyProof.selector,
                acceptorData.root, 1, signalHash, acceptorData.nullifierHash, externalNullifier, acceptorData.proof
            )
        );

        controller.checkAcceptor(acceptor, "", abi.encode(acceptorData));
    }

    function test_shouldReturnInterfaceId() external {
        assertEq(
            controller.checkAcceptor(acceptor, "", abi.encode(acceptorData)),
            type(IPWNAcceptorController).interfaceId
        );
    }

}
