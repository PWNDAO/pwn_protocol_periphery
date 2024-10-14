// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { UniV3PosStateFingerpringComputer }  from "src/state-fingerprint-computer/UniV3PosStateFingerpringComputer.sol";

import { PWNSimpleLoanProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";

import {
    UseCasesTest,
    MultiToken,
    IERC721
} from "pwn_contracts/test/fork/UseCases.fork.t.sol";


interface UniV3PostLike {
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
}

contract UniV3PosStateFingerprintComputerForkTest is UseCasesTest {

    address constant UNI_V3_POS = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    uint256 collId = 1;

    UniV3PosStateFingerpringComputer computer;

    constructor() {
        deploymentsSubpath = "/lib/pwn_contracts";
    }

    function setUp() override public {
        super.setUp();

        computer = new UniV3PosStateFingerpringComputer(UNI_V3_POS);
        vm.prank(deployment.config.owner());
        deployment.config.registerStateFingerprintComputer(UNI_V3_POS, address(computer));

        collId = 1;
        address originalOwner = IERC721(UNI_V3_POS).ownerOf(collId);
        vm.prank(originalOwner);
        IERC721(UNI_V3_POS).transferFrom(originalOwner, borrower, collId);

        vm.prank(borrower);
        IERC721(UNI_V3_POS).setApprovalForAll(address(deployment.simpleLoan), true);
    }

    function test_shouldFail_whenUniV3PosStateChanges() external {
        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = UNI_V3_POS;
        proposal.collateralId = collId;
        proposal.collateralAmount = 0;
        proposal.checkCollateralStateFingerprint = true;
        proposal.collateralStateFingerprint = computer.computeStateFingerprint(UNI_V3_POS, collId);

        vm.prank(borrower);
        UniV3PostLike(UNI_V3_POS).decreaseLiquidity(UniV3PostLike.DecreaseLiquidityParams({
            tokenId: collId,
            liquidity: 100,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 1 days
        }));
        bytes32 currentFingerprint = computer.computeStateFingerprint(UNI_V3_POS, collId);

        assertTrue(currentFingerprint != proposal.collateralStateFingerprint);

        // Create loan
        _createLoanRevertWith(
            abi.encodeWithSelector(
                PWNSimpleLoanProposal.InvalidCollateralStateFingerprint.selector,
                currentFingerprint,
                proposal.collateralStateFingerprint
            )
        );
    }

    function test_shouldPass_whenUniV3PosStateDoesNotChange() external {
        // Define proposal
        proposal.collateralCategory = MultiToken.Category.ERC721;
        proposal.collateralAddress = UNI_V3_POS;
        proposal.collateralId = collId;
        proposal.collateralAmount = 0;
        proposal.checkCollateralStateFingerprint = true;
        proposal.collateralStateFingerprint = computer.computeStateFingerprint(UNI_V3_POS, collId);

        // Create loan
        _createLoan();

        // Check balance
        assertEq(IERC721(UNI_V3_POS).ownerOf(collId), address(deployment.simpleLoan));
    }

}