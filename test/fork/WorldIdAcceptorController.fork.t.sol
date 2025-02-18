// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken, IERC20 } from "MultiToken/MultiToken.sol";

import {
    WorldIdAcceptorController,
    IWorldID
} from "src/acceptor-controller/WorldIdAcceptorController.sol";

import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { PWNSimpleLoan } from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanSimpleProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanSimpleProposal.sol";

import {
    DeploymentTest,
    PWNSimpleLoan,
    PWNSimpleLoanSimpleProposal
} from "pwn_contracts/test/DeploymentTest.t.sol";


contract WorldIdAcceptorControllerForkTest is DeploymentTest {

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant aUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    IWorldID constant worldId = IWorldID(0x17B354dD2595411ff79041f930e491A4Df39A278);
    string constant appId = "app_17abe44eaf47c99566f5378aa4e19463";
    string constant actionId = "verify-humanness";

    WorldIdAcceptorController controller;

    constructor() {
        deploymentsSubpath = "/lib/pwn_contracts";
    }

    function setUp() override public {
        vm.createSelectFork("world");

        super.setUp();

        controller = new WorldIdAcceptorController(worldId, appId, actionId);
        deployment.simpleLoanSimpleProposal = new PWNSimpleLoanSimpleProposal(
            address(deployment.hub),
            address(deployment.revokedNonce),
            address(deployment.config),
            address(deployment.utilizedCredit)
        );

        address[] memory addresses = new address[](2);
        addresses[0] = address(deployment.simpleLoanSimpleProposal);
        addresses[1] = address(deployment.simpleLoanSimpleProposal);
        bytes32[] memory tags = new bytes32[](2);
        tags[0] = PWNHubTags.LOAN_PROPOSAL;
        tags[1] = PWNHubTags.NONCE_MANAGER;

        vm.prank(deployment.protocolTimelock);
        deployment.hub.setTags(addresses, tags, true);

        vm.startPrank(aUSDC);
        IERC20(USDC).transfer(lender, 100e6);
        IERC20(USDC).transfer(borrower, 100e6);
        vm.stopPrank();

        vm.prank(lender);
        IERC20(USDC).approve(address(deployment.simpleLoan), type(uint256).max);
        vm.prank(borrower);
        IERC20(USDC).approve(address(deployment.simpleLoan), type(uint256).max);
    }

    function test_shouldPass_whenValidWorldId() external {
        PWNSimpleLoan.LenderSpec memory lenderSpec = PWNSimpleLoan.LenderSpec(lender);

        PWNSimpleLoanSimpleProposal.Proposal memory proposal = PWNSimpleLoanSimpleProposal.Proposal({
            collateralCategory: MultiToken.Category.ERC20,
            collateralAddress: USDC,
            collateralId: 0,
            collateralAmount: 10e6,
            checkCollateralStateFingerprint: false,
            collateralStateFingerprint: bytes32(0),
            creditAddress: USDC,
            creditAmount: 10e6,
            availableCreditLimit: 0,
            utilizedCreditId: bytes32(0),
            fixedInterestAmount: 0,
            accruingInterestAPR: 0,
            durationOrDate: 5 days,
            expiration: uint40(block.timestamp + 5 days),
            acceptorController: address(controller),
            acceptorControllerData: "",
            proposer: lender,
            proposerSpecHash: keccak256(abi.encode(lenderSpec)),
            isOffer: true,
            refinancingLoanId: 0,
            nonceSpace: 0,
            nonce: 0,
            loanContract: address(deployment.simpleLoan)
        });

        PWNSimpleLoanSimpleProposal.ProposalValues memory proposalValues = PWNSimpleLoanSimpleProposal.ProposalValues({
            acceptorControllerData: abi.encode(WorldIdAcceptorController.AcceptorData({
                root: 0,
                nullifierHash: 1,
                proof: [uint256(2), 3, 4, 5, 6, 7, 8, 9]
            }))
        });

        vm.prank(lender);
        deployment.simpleLoanSimpleProposal.makeProposal(proposal);

        bytes memory proposalData = deployment.simpleLoanSimpleProposal.encodeProposalData(proposal, proposalValues);

        vm.prank(borrower);
        deployment.simpleLoan.createLOAN({
            proposalSpec: PWNSimpleLoan.ProposalSpec({
                proposalContract: address(deployment.simpleLoanSimpleProposal),
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
