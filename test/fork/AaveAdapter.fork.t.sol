// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import {
    AaveAdapter,
    IAavePoolLike
} from "src/pool-adapter/AaveAdapter.sol";

import { PWNSimpleLoan } from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanSimpleProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanSimpleProposal.sol";

import { T20 } from "pwn_protocol/test/helper/T20.sol";
import {
    UseCasesTest,
    MultiToken,
    IERC20
} from "pwn_protocol/test/fork/UseCases.fork.t.sol";


contract AaveAdapterForkTest is UseCasesTest {

    address constant AAVE = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant aDAI = 0x018008bfb33d285247A21d44E50697654f754e63;

    uint256 initialAmount = 1000e18;

    AaveAdapter adapter;

    constructor() {
        deploymentsSubpath = "/lib/pwn_protocol";
    }

    function setUp() override public {
        super.setUp();

        adapter = new AaveAdapter(address(__d.hub));
        vm.prank(__d.config.owner());
        __d.config.registerPoolAdapter(AAVE, address(adapter));

        deal(DAI, lender, initialAmount);

        // Supply to pool 1k DAI
        vm.startPrank(lender);
        IERC20(DAI).approve(AAVE, type(uint256).max);
        IAavePoolLike(AAVE).supply(DAI, initialAmount, lender, 0);
        IERC20(aDAI).approve(address(adapter), type(uint256).max);
        IERC20(DAI).approve(address(__d.simpleLoan), type(uint256).max);
        vm.stopPrank();

        vm.prank(borrower);
        IERC20(DAI).approve(address(__d.simpleLoan), type(uint256).max);
    }

    function test_shouldWithdrawAndRepayToPool() external {
        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: AAVE
        });

        // Update proposal
        proposal.creditAddress = DAI;
        proposal.creditAmount = 100e18; // 100 DAI
        proposal.proposerSpecHash = __d.simpleLoan.getLenderSpecHash(lenderSpec);

        assertApproxEqAbs(IERC20(aDAI).balanceOf(lender), initialAmount, 1);
        assertEq(IERC20(DAI).balanceOf(lender), 0);
        assertEq(IERC20(DAI).balanceOf(borrower), 0);

        // Make proposal
        vm.prank(lender);
        __d.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = __d.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create loan
        vm.prank(borrower);
        uint256 loanId = __d.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(__d.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: lenderSpec,
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });

        // Check balance
        assertApproxEqAbs(IERC20(aDAI).balanceOf(lender), initialAmount - proposal.creditAmount, 1);
        assertEq(IERC20(DAI).balanceOf(lender), 0);
        assertEq(IERC20(DAI).balanceOf(borrower), proposal.creditAmount);

        // Move in time
        vm.warp(block.timestamp + 20 hours);

        // Repay loan
        vm.prank(borrower);
        __d.simpleLoan.repayLOAN(loanId);

        // LOAN token owner is original lender -> repay funds to the pool
        assertGe(IERC20(aDAI).balanceOf(lender), initialAmount); // greater than or equal because pool may have accrued interest
        assertEq(IERC20(DAI).balanceOf(lender), 0);
        assertEq(IERC20(DAI).balanceOf(borrower), 0);
        vm.expectRevert("ERC721: invalid token ID");
        __d.loanToken.ownerOf(loanId);
    }

    function test_shouldWithdrawFromPoolAndRepayToVault() external {
        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: AAVE
        });

        // Update proposal
        proposal.creditAddress = DAI;
        proposal.creditAmount = 100e18; // 100 DAI
        proposal.proposerSpecHash = __d.simpleLoan.getLenderSpecHash(lenderSpec);

        assertApproxEqAbs(IERC20(aDAI).balanceOf(lender), 1000e18, 1);
        assertEq(IERC20(DAI).balanceOf(lender), 0);
        assertEq(IERC20(DAI).balanceOf(borrower), 0);

        // Make proposal
        vm.prank(lender);
        __d.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = __d.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create loan
        vm.prank(borrower);
        uint256 loanId = __d.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(__d.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: lenderSpec,
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });

        // Check balance
        assertApproxEqAbs(IERC20(aDAI).balanceOf(lender), 900e18, 1);
        assertEq(IERC20(DAI).balanceOf(lender), 0);
        assertEq(IERC20(DAI).balanceOf(borrower), 100e18);

        // Move in time
        vm.warp(block.timestamp + 20 hours);

        address newLender = makeAddr("new lender");

        vm.prank(lender);
        __d.loanToken.transferFrom(lender, newLender, loanId);

        uint256 originalBalance = IERC20(DAI).balanceOf(address(__d.simpleLoan));

        // Repay loan
        vm.prank(borrower);
        __d.simpleLoan.repayLOAN(loanId);

        // LOAN token owner is not original lender -> repay funds to the Vault
        assertGe(IERC20(aDAI).balanceOf(lender), 900e18);
        assertEq(IERC20(DAI).balanceOf(address(__d.simpleLoan)), originalBalance + 100e18);
        assertEq(__d.loanToken.ownerOf(loanId), newLender);
    }

    // This fuzz test fails randomly. Use the failed credit amount directly and the test will pass.
    function testFuzz_shouldWithdrawAnyAmount(uint256 creditAmount) external {
        creditAmount = bound(creditAmount, 1, initialAmount / 1e18) * 1e18;

        vm.warp(block.timestamp + 10);

        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: AAVE
        });

        // Update proposal
        proposal.creditAddress = DAI;
        proposal.creditAmount = creditAmount;
        proposal.proposerSpecHash = __d.simpleLoan.getLenderSpecHash(lenderSpec);

        assertEq(IERC20(DAI).balanceOf(borrower), 0);

        // Make proposal
        vm.prank(lender);
        __d.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = __d.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Create loan
        vm.prank(borrower);
        __d.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(__d.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: lenderSpec,
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });

        // Check balance
        assertEq(IERC20(DAI).balanceOf(borrower), creditAmount);
    }

    function test_shouldFail_whenPostWithdrawHFUnderMin() external {
        // Set min HF to 1.5
        vm.prank(lender);
        adapter.setMinHealthFactor(1.5e18);

        // Create some debt
        vm.prank(lender);
        IAavePoolLike(AAVE).borrow(DAI, 500e18, 2, 0, lender);

        // Update lender spec
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec({
            sourceOfFunds: AAVE
        });

        // Update proposal
        proposal.creditAddress = DAI;
        proposal.creditAmount = 100e18; // 100 DAI
        proposal.proposerSpecHash = __d.simpleLoan.getLenderSpecHash(lenderSpec);

        // Make proposal
        vm.prank(lender);
        __d.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = __d.simpleLoanSimpleProposal.encodeProposalData(proposal);

        // Try to create loan
        vm.expectRevert();
        vm.prank(borrower);
        __d.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(__d.simpleLoanSimpleProposal),
                proposalData: proposalData,
                proposalInclusionProof: new bytes32[](0),
                signature: ""
            }),
            lenderSpec: lenderSpec,
            callerSpec: PWNSimpleLoan.CallerSpec({
                refinancingLoanId: 0,
                revokeNonce: false,
                nonce: 0
            }),
            extra: ""
        });
    }

}
