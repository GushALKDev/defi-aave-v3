// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {Aave} from "../lib/Aave.sol";
import {Swap} from "../lib/Swap.sol";
import {Math} from "../lib/Math.sol";

// NOTE: Don't use this contract in production.
// Any caller can borrow on behalf of this contract and withdraw collateral from this contract.

contract LongShort is Aave, Swap {
    struct OpenParams {
        address collateralToken;
        uint256 collateralAmount;
        address borrowToken;
        uint256 borrowAmount;
        // Minimum health factor after borrowing token
        uint256 minHealthFactor;
        uint256 minSwapAmountOut;
        // Arbitrary data to be passed to the swap function
        bytes swapData;
    }

    // Approve this contract to pull in collateral
    // Approve this contract to borrow
    // Task 1 - Open a long or a short position
    function open(OpenParams memory params)
        public
        returns (uint256 collateralAmountOut)
    {
        // Task 1.1 - Check that params.minHealthFactor is greater than 1e18
        require(params.minHealthFactor > 1e18, "minHealthFactor too low");

        // Task 1.2 - Transfer collateral from msg.sender
        IERC20(params.collateralToken).transferFrom(msg.sender, address(this), params.collateralAmount);

        // Task 1.3
        // - Approve and supply collateral to Aave
        // - Send aToken to msg.sender
        IERC20(params.collateralToken).approve(address(Aave.pool), params.collateralAmount);
        Aave.pool.supply({
            asset: params.collateralToken,
            amount: params.collateralAmount,
            onBehalfOf: msg.sender,
            referralCode: 0
        });

        // Task 1.4
        // - Borrow token from Aave
        // - Borrow on behalf of msg.sender
        pool.borrow({
            asset: params.borrowToken,
            amount: params.borrowAmount,
            interestRateMode: 2,
            referralCode: 0,
            onBehalfOf: msg.sender
        });

        // Task 1.5 - Check that health factor of msg.sender is > params.minHealthFactor
        require(getHealthFactor(msg.sender) >= params.minHealthFactor, "health factor < min");
        
        // Task 1.6
        // - Swap borrowed token to collateral token
        IERC20(params.borrowToken).approve(address(Swap.router), params.borrowAmount);

        uint256 swapAmountOut = Swap.swap({
            tokenIn: params.borrowToken,
            tokenOut: params.collateralToken,
            amountIn: params.borrowAmount,
            amountOutMin: params.minSwapAmountOut,
            receiver: msg.sender,
            data: params.swapData
        });

        collateralAmountOut = swapAmountOut;
    }

    struct CloseParams {
        address collateralToken;
        uint256 collateralAmount;
        uint256 maxCollateralToWithdraw;
        address borrowToken;
        uint256 maxDebtToRepay;
        uint256 minSwapAmountOut;
        // Arbitrary data to be passed to the swap function
        bytes swapData;
    }

    // Collateral (USDC) ----> Borrowed token (ETH) -----> Swap -----> Collateral (USDC)

    // Approve this contract to pull in collateral AToken
    // Approve this contract to pull in collateral
    // Approve this contract to pull in borrowed token if closing at a loss
    // Task 2 - Close a long or a short position
    function close(CloseParams memory params)
        public
        returns (
            uint256 collateralWithdrawn,
            uint256 debtRepaidFromMsgSender,
            uint256 borrowedLeftover
        )
    {
        // Task 2.1 - Transfer collateral from msg.sender into this contract
        IERC20(params.collateralToken).transferFrom(msg.sender, address(this), params.collateralAmount);

        // Task 2.2 - Swap collateral to borrowed token
        IERC20(params.collateralToken).approve(address(Swap.router), params.collateralAmount);
        uint256 swapAmountOut = Swap.swap({
            tokenIn: params.collateralToken,
            tokenOut: params.borrowToken,
            amountIn: params.collateralAmount,
            amountOutMin: params.minSwapAmountOut,
            receiver: address(this),
            data: params.swapData
        });

        // Task 2.3
        // - Repay borrowed token
        uint256 currentDebt = Aave.getVariableDebt(params.borrowToken, msg.sender);
        
        // - Amount to repay is the minimum of current debt and params.maxDebtToRepay
        uint256 debtToRepay = Math.min(currentDebt, params.maxDebtToRepay);
        
        // - If the amount to repay is greater that the amount swapped,
        //   then transfer the difference from msg.sender
        uint256 repayAmount = 0;
        if (debtToRepay > swapAmountOut) {
            repayAmount = debtToRepay - swapAmountOut;
            IERC20(params.borrowToken).transferFrom(msg.sender, address(this), repayAmount);
        }

        IERC20(params.borrowToken).approve(address(Aave.pool), debtToRepay);
        Aave.pool.repay({
            asset: params.borrowToken,
            amount: debtToRepay,
            interestRateMode: 2,
            onBehalfOf: msg.sender
        });
        
        // Task 2.4 - Withdraw collateral to msg.sender
        // Transfer aTokens from msg.sender to this contract
        address aTokenAddress = Aave.getATokenAddress(params.collateralToken);
        uint256 aTokenBalance = IERC20(aTokenAddress).balanceOf(msg.sender);
        uint256 amountToWithdraw = Math.min(aTokenBalance, params.maxCollateralToWithdraw);
        
        IERC20(aTokenAddress).transferFrom(msg.sender, address(this), amountToWithdraw);
        
        uint256 withdrawn = Aave.pool.withdraw({
            asset: params.collateralToken,
            amount: amountToWithdraw,
            to: msg.sender
        });

        // Task 2.5 - Transfer profit = swapped amount - repaid amount
        uint256 balanceBorrowToken = IERC20(params.borrowToken).balanceOf(address(this));
        if (balanceBorrowToken > 0) {
            IERC20(params.borrowToken).transfer(msg.sender, balanceBorrowToken);
        }

        // Task 2.6 - Return amount of collateral withdrawn,
        // debt repaid and profit from closing this position
        return (withdrawn, repayAmount, balanceBorrowToken);
    }
}
