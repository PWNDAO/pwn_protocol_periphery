// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { IPWNAcceptorController } from "pwn/interfaces/IPWNAcceptorController.sol";


interface IWorldID {

    /**
     * @notice Reverts if the zero-knowledge proof is invalid.
     * @param root The of the Merkle tree.
     * @param groupId The id of the Semaphore group.
     * @param signalHash A keccak256 hash of the Semaphore signal.
     * @param nullifierHash The nullifier hash.
     * @param externalNullifierHash A keccak256 hash of the external nullifier.
     * @param proof The zero-knowledge proof.
     * @dev  Note that a double-signaling check is not included here, and should be carried by the caller.
     */
    function verifyProof(
        uint256 root,
        uint256 groupId,
        uint256 signalHash,
        uint256 nullifierHash,
        uint256 externalNullifierHash,
        uint256[8] calldata proof
    ) external view;

}


contract WorldIdAcceptorController is IPWNAcceptorController {

    /**
     * @dev The World ID instance that will be used for verifying proofs
     */
	IWorldID internal immutable worldId;
    /**
     * @dev The contract's external nullifier hash
     */
    uint256 internal immutable externalNullifier;
    /**
     * @dev The World ID group ID (always 1)
     */
    uint256 internal immutable groupId = 1;

    /**
     * @dev Reverts if the proposer data is not empty.
     */
    error NonEmptyProposerData();

    /**
     * @notice The data that the acceptor must provide to the controller.
     * @param root The root of the Merkle tree.
     * @param nullifierHash The nullifier hash for this proof.
     * @param proof The zero-knowledge proof.
     */
    struct AcceptorData {
        uint256 root;
        uint256 nullifierHash;
        uint256[8] proof;
    }


    constructor(IWorldID _worldId, string memory _appId, string memory _actionId) {
        worldId = _worldId;
        externalNullifier = _hashToField(abi.encodePacked(_hashToField(abi.encodePacked(_appId)), _actionId));
    }


    /**
     * @inheritdoc IPWNAcceptorController
     */
    function checkAcceptor(
        address acceptor, bytes calldata proposerData, bytes calldata acceptorData
    ) external view returns (bytes4) {
        if (proposerData.length > 0) {
            revert NonEmptyProposerData();
        }

        AcceptorData memory data = abi.decode(acceptorData, (AcceptorData));

        worldId.verifyProof(
			data.root,
			groupId,
			_hashToField(abi.encodePacked(acceptor)),
			data.nullifierHash,
			externalNullifier,
			data.proof
		);

        return type(IPWNAcceptorController).interfaceId;
    }

    /**
     * @dev Creates a keccak256 hash of a bytestring.
     * @param value The bytestring to hash
     * @return The hash of the specified value
     * @dev `>> 8` makes sure that the result is included in our field
     */
    function _hashToField(bytes memory value) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(value))) >> 8;
    }

}
