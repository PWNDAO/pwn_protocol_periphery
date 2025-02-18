// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { WorldIdAcceptorController, IWorldID } from "src/acceptor-controller/WorldIdAcceptorController.sol";


contract WorldIdAcceptorControllerHarness is WorldIdAcceptorController {

    constructor(IWorldID _worldId, string memory _appId, string memory _actionId) WorldIdAcceptorController(_worldId, _appId, _actionId) {}

    function exposed_hashToField(bytes memory input) public pure returns (uint256) {
        return _hashToField(input);
    }

}
