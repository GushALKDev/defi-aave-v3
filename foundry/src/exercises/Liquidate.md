# Aave V3 Liquidation Exercise: Complete Guide

## Table of Contents
- [Introduction](#introduction)
- [What is Liquidation?](#what-is-liquidation)
- [Prerequisites](#prerequisites)
- [Exercise Overview](#exercise-overview)
- [Step-by-Step Implementation](#step-by-step-implementation)
- [Understanding the Test Scenario](#understanding-the-test-scenario)
- [Key Concepts](#key-concepts)
- [Common Pitfalls](#common-pitfalls)
- [Running the Tests](#running-the-tests)
- [Further Learning](#further-learning)

---

## Introduction

This exercise teaches you how to implement a liquidation function for Aave V3, one of the most critical mechanisms in DeFi lending protocols. Liquidations help maintain protocol solvency by allowing third parties (liquidators) to repay under-collateralized loans in exchange for the borrower's collateral at a discount.

**Learning Objectives:**
- Understand the liquidation process in Aave V3
- Learn how to query debt information from the protocol
- Implement a basic liquidator contract
- Understand the role of health factors in liquidations

---

## What is Liquidation?

### The Problem
When a user borrows assets from Aave, they must provide collateral. If the value of their collateral drops (or their debt increases due to interest), their position becomes **under-collateralized**. This poses a risk to the protocol because the debt might exceed the collateral value.

### The Solution
Liquidation allows anyone to repay part (or all) of an under-collateralized user's debt in exchange for their collateral plus a bonus. This mechanism:
- Protects the protocol from bad debt
- Creates arbitrage opportunities for liquidators
- Incentivizes maintaining healthy positions

### When Can Liquidation Occur?
A position can be liquidated when its **health factor** drops below 1:

```
Health Factor = (Total Collateral × Liquidation Threshold) / Total Debt
```

If `Health Factor < 1`, the position is under-collateralized and eligible for liquidation.

---

## Prerequisites

Before starting this exercise, you should understand:
- How Aave's supply and borrow functions work
- ERC20 token transfers and approvals
- The concept of collateralization ratios
- Basic Solidity and smart contract interactions

**Required Setup:**
- Foundry installed
- Environment variables set:
  - `$FORK_URL` - Ethereum mainnet RPC URL
  - `$FORK_BLOCK_NUM` - Block number to fork from

---

## Exercise Overview

**Goal:** Implement a `liquidate` function that repays a user's debt and receives their collateral.

**Contract Location:** `foundry/src/exercises/Liquidate.sol`

**Function Signature:**
```solidity
function liquidate(
    address collateral,      // The collateral token to receive
    address borrowedToken,   // The token borrowed by the user
    address user             // The user with under-collateralized debt
) public
```

**What You Need to Do:**
1. Query the user's debt amount
2. Transfer the debt amount from the caller to the contract
3. Approve Aave Pool to spend the debt tokens
4. Call Aave's `liquidationCall` function

---

## Step-by-Step Implementation

### Step 1: Get the User's Debt Amount

First, we need to determine how much the user owes. Aave uses **variable debt tokens** to track each user's debt for each asset.

```solidity
// Task 1.1 - Get the amount of borrowed token that the user owes to Aave V3
IPool.ReserveData memory reserveData = pool.getReserveData(borrowedToken);
uint256 totalDebtBase = IERC20(reserveData.variableDebtTokenAddress).balanceOf(user);
```

**Explanation:**
- `pool.getReserveData(borrowedToken)` returns information about the borrowed token's reserve, including the address of the variable debt token
- `ReserveData` is a struct containing various addresses and configuration for an asset
- `variableDebtTokenAddress` is the address of the ERC20-like token representing variable rate debt
- We check the `balanceOf` this debt token for the user to see how much they owe

**Why this works:**
In Aave V3, when you borrow an asset, you receive "debt tokens" that represent your obligation. The balance of these tokens equals your debt amount. These tokens are not transferable but they accrue interest over time.

---

### Step 2: Transfer Borrowed Tokens from Caller

The liquidator (caller) must provide the tokens to repay the debt. We transfer these tokens from `msg.sender` to our contract.

```solidity
// Task 1.2 - Transfer the full borrowed amount from msg.sender
IERC20(borrowedToken).transferFrom(msg.sender, address(this), totalDebtBase);
```

**Explanation:**
- `transferFrom` requires the caller (`msg.sender`) to have previously approved our contract
- We transfer the exact debt amount to our contract
- This contract will then use these tokens to repay the user's debt

**Important Note:**
Before calling this function, `msg.sender` must:
1. Have enough `borrowedToken` balance
2. Have approved this contract to spend at least `totalDebtBase` amount

---

### Step 3: Approve the Pool Contract

Now our contract has the borrowed tokens, but the Aave Pool needs permission to spend them to repay the debt.

```solidity
// Task 1.3 - Approve the pool contract to spend borrowed token from this contract
IERC20(borrowedToken).approve(address(pool), totalDebtBase);
```

**Explanation:**
- We approve the Aave Pool contract to spend our borrowed tokens
- The Pool will pull these tokens when we call `liquidationCall`
- We approve the exact amount needed for the liquidation

**Security Note:**
In production, you might want to use `safeApprove` or set approval to 0 after the liquidation to follow best practices.

---

### Step 4: Execute the Liquidation

Finally, we call Aave's `liquidationCall` function to execute the liquidation.

```solidity
// Task 1.4 - Call liquidate
pool.liquidationCall({
    collateralAsset: collateral,
    debtAsset: borrowedToken,
    user: user,
    debtToCover: totalDebtBase,
    receiveAToken: false
});
```

**Parameter Breakdown:**

- **`collateralAsset`**: The address of the collateral token you want to receive (e.g., WETH)
  - This is the asset the user deposited as collateral
  
- **`debtAsset`**: The address of the token that was borrowed (e.g., DAI)
  - This is what we're repaying
  
- **`user`**: The address of the borrower being liquidated
  - Must have a health factor < 1
  
- **`debtToCover`**: The amount of debt to repay
  - Can be partial or full debt
  - We're using the full debt amount
  
- **`receiveAToken`**: Whether to receive aTokens or the underlying asset
  - `false` = receive the underlying collateral token (WETH, DAI, etc.)
  - `true` = receive aTokens (which continue earning interest)

**What Happens Inside `liquidationCall`:**
1. Validates the user's health factor is below threshold
2. Calculates how much collateral to seize based on:
   - Amount of debt being repaid
   - Current prices of debt and collateral assets
   - Liquidation bonus (typically 5-10%)
3. Burns the user's debt tokens
4. Transfers collateral to the liquidator
5. Transfers a protocol fee portion (if configured)

**The Liquidation Bonus:**
The liquidator receives more collateral value than the debt they repay. For example:
- You repay $1000 of debt
- You receive $1050 worth of collateral (5% bonus)
- The $50 is your profit for providing the liquidation service

---

## Understanding the Test Scenario

Let's break down what happens in the test file (`test/Liquidate.test.sol`):

### Setup Phase

```solidity
function setUp() public {
    // 1. Supply 1 WETH as collateral
    deal(WETH, address(this), 1e18);
    weth.approve(address(pool), type(uint256).max);
    pool.supply({
        asset: WETH,
        amount: 1e18,
        onBehalfOf: address(this),
        referralCode: 0
    });

    // 2. Mock ETH price at $2000
    vm.mockCall(
        ORACLE,
        abi.encodeCall(IAaveOracle.getAssetPrice, (WETH)),
        abi.encode(uint256(2000 * 1e8))
    );
    
    // 3. Borrow 1000 DAI against the WETH collateral
    pool.borrow({
        asset: DAI,
        amount: 1000 * 1e18,
        interestRateMode: 2,
        referralCode: 0,
        onBehalfOf: address(this)
    });

    // 4. Mock ETH price crash to $500 (4x drop!)
    uint256 ethPrice = 500 * 1e8;
    vm.mockCall(
        ORACLE,
        abi.encodeCall(IAaveOracle.getAssetPrice, (WETH)),
        abi.encode(ethPrice)
    );

    // 5. Setup liquidator contract with DAI
    target = new Liquidate();
    deal(DAI, address(this), 10000 * 1e18);
    dai.approve(address(target), 10000 * 1e18);
}
```

**What's Happening:**
1. Test contract supplies 1 WETH (~$2000 collateral)
2. Borrows 1000 DAI (assuming 80% LTV, this is safe)
3. ETH price crashes from $2000 to $500
4. Collateral is now only worth $500, but debt is still $1000
5. Position is heavily under-collateralized and ready for liquidation

**Health Factor Calculation:**
```
Before crash:
- Collateral value: 1 ETH × $2000 = $2000
- Debt value: 1000 DAI = $1000
- Health Factor ≈ (2000 × 0.825) / 1000 = 1.65 ✅ Healthy

After crash:
- Collateral value: 1 ETH × $500 = $500
- Debt value: 1000 DAI = $1000
- Health Factor ≈ (500 × 0.825) / 1000 = 0.4125 ❌ Under-collateralized!
```

### Test Execution

```solidity
function test_liquidate() public {
    // Get user's data before liquidation
    (uint256 colUsdBefore, uint256 debtUsdBefore,,,,) =
        pool.getUserAccountData(address(this));

    // Execute liquidation
    target.liquidate(WETH, DAI, address(this));

    // Get user's data after liquidation
    (uint256 colUsdAfter, uint256 debtUsdAfter,,,,) =
        pool.getUserAccountData(address(this));

    // Verify collateral and debt decreased
    assertLt(colUsdAfter, colUsdBefore, "USD collateral after");
    assertLt(debtUsdAfter, debtUsdBefore, "USD debt after");

    // Verify liquidator received WETH
    uint256 wethBal = weth.balanceOf(address(target));
    console.log("WETH balance: %e", wethBal);
    assertGt(wethBal, 0, "WETH balance");
}
```

**Assertions Explained:**
1. `colUsdAfter < colUsdBefore` - User's collateral decreased (seized by liquidator)
2. `debtUsdAfter < debtUsdBefore` - User's debt decreased (repaid by liquidator)
3. `wethBal > 0` - Liquidator received WETH collateral

---

## Key Concepts

### 1. Variable Debt Tokens
In Aave V3, debt is represented by special tokens:
- **Variable Debt Tokens**: Represent debt with variable interest rates
- These tokens are **non-transferable**
- Balance increases over time as interest accrues
- Burned when debt is repaid

### 2. Reserve Data Structure
The `getReserveData` function returns critical information about each asset:
```solidity
struct ReserveData {
    uint256 configuration;
    uint128 liquidityIndex;
    uint128 variableBorrowIndex;
    uint128 currentLiquidityRate;
    uint128 currentVariableBorrowRate;
    uint40 lastUpdateTimestamp;
    address aTokenAddress;              // Receipt token for suppliers
    address stableDebtTokenAddress;     // Stable rate debt token
    address variableDebtTokenAddress;   // Variable rate debt token (we use this!)
    address interestRateStrategyAddress;
    uint8 id;
}
```

### 3. Liquidation Mechanics

**Close Factor:**
- Maximum percentage of debt that can be liquidated in one transaction
- Typically 50% if health factor is between 0.95 and 1.0
- 100% if health factor is below 0.95

**Liquidation Bonus:**
- Extra collateral given to liquidators as incentive
- Typically 5-10% depending on the asset
- Example: Repay $1000 debt, receive $1050 collateral

**Protocol Fee:**
- Portion of the liquidation bonus that goes to the protocol reserve
- Taken from the liquidation bonus
- Example: 10% of the bonus might go to protocol treasury

### 4. Health Factor

The health factor determines if a position can be liquidated:

```
Health Factor = (Σ Collateral in ETH × Liquidation Threshold) / Total Borrows in ETH
```

**States:**
- `HF > 1.0`: Position is healthy, cannot be liquidated
- `0.95 < HF < 1.0`: Partially liquidatable (usually 50% close factor)
- `HF < 0.95`: Fully liquidatable (100% close factor)

**Liquidation Threshold vs LTV:**
- **LTV (Loan-to-Value)**: Maximum borrowing power (e.g., 80%)
- **Liquidation Threshold**: When liquidation occurs (e.g., 85%)
- The gap between them provides a safety buffer

---

## Common Pitfalls

### 1. Insufficient Approval
❌ **Mistake:**
```solidity
// Forgot to approve the pool
pool.liquidationCall({...});  // Will fail!
```

✅ **Solution:**
```solidity
IERC20(borrowedToken).approve(address(pool), totalDebtBase);
pool.liquidationCall({...});
```

### 2. Wrong Debt Token Address
❌ **Mistake:**
```solidity
// Using the asset address instead of debt token address
uint256 debt = IERC20(borrowedToken).balanceOf(user);  // Wrong!
```

✅ **Solution:**
```solidity
// Get the debt token address first
IPool.ReserveData memory reserve = pool.getReserveData(borrowedToken);
uint256 debt = IERC20(reserve.variableDebtTokenAddress).balanceOf(user);
```

### 3. Not Handling Partial Liquidations
❌ **Mistake:**
```solidity
// Always trying to liquidate full debt might fail if health factor > 0.95
pool.liquidationCall({
    debtToCover: totalDebt,  // Might exceed close factor!
    ...
});
```

✅ **Solution:**
Consider checking health factor and adjusting debt to cover accordingly, or use `type(uint256).max` to let Aave calculate the maximum:
```solidity
pool.liquidationCall({
    debtToCover: type(uint256).max,  // Aave will calculate max allowed
    ...
});
```

### 4. Forgetting to Transfer Tokens First
❌ **Mistake:**
```solidity
// Trying to liquidate without having borrowed tokens
pool.liquidationCall({...});  // Contract has no tokens!
```

✅ **Solution:**
```solidity
IERC20(borrowedToken).transferFrom(msg.sender, address(this), debt);
IERC20(borrowedToken).approve(address(pool), debt);
pool.liquidationCall({...});
```

### 5. Incorrect Asset Order
❌ **Mistake:**
```solidity
pool.liquidationCall({
    collateralAsset: DAI,   // Wrong order!
    debtAsset: WETH,
    ...
});
```

✅ **Solution:**
```solidity
pool.liquidationCall({
    collateralAsset: WETH,  // What you want to receive
    debtAsset: DAI,         // What you're repaying
    ...
});
```

---

## Running the Tests

### Setup Environment Variables

```bash
# Set your Ethereum RPC URL
export FORK_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"

# Set a specific block number (optional but recommended for consistent tests)
export FORK_BLOCK_NUM=18000000
```

### Run the Test

```bash
cd foundry
forge test --fork-url $FORK_URL --fork-block-number $FORK_BLOCK_NUM --match-path test/Liquidate.test.sol -vvv
```

**Flag Explanations:**
- `--fork-url`: Ethereum mainnet RPC endpoint to fork from
- `--fork-block-number`: Specific block to fork (ensures consistent state)
- `--match-path`: Only run tests in this specific file
- `-vvv`: Verbose output (shows console.log statements and call traces)

### Expected Output

```
Running 1 test for test/Liquidate.test.sol:LiquidateTest
[PASS] test_liquidate() (gas: ~500000)
Logs:
  WETH balance: 1.0e18

Test result: ok. 1 passed; 0 failed; finished in 2.34s
```

### Troubleshooting

**Test fails with "Transfer amount exceeds balance":**
- The caller doesn't have enough borrowed tokens
- Check that the test `deal` function properly funded the account

**Test fails with "Health factor not below threshold":**
- The user's position is not under-collateralized
- Verify the price oracle mock is setting the correct price

**Test fails with "Insufficient allowance":**
- Missing approval to transfer tokens
- Check both approvals: caller → contract, and contract → pool

---

## Further Learning

### Next Steps

1. **Implement Profitability Checks:**
   - Calculate if liquidation is profitable after gas costs
   - Compare liquidation bonus vs transaction fees

2. **Add Flash Loan Integration:**
   - Use Aave flash loans to borrow repayment tokens
   - Repay flash loan from liquidation proceeds
   - Keep the profit

3. **Multi-Collateral Liquidations:**
   - Handle users with multiple collateral types
   - Determine which collateral is most profitable to seize

4. **Bot Development:**
   - Monitor health factors continuously
   - Execute liquidations automatically when profitable
   - Handle competition with other liquidators

### Advanced Topics

- **MEV (Maximal Extractable Value)**: How liquidators compete for profitable opportunities
- **Liquidation Strategies**: Optimal timing and asset selection
- **Gas Optimization**: Reducing costs to increase profitability
- **Flash Loan Liquidations**: Using borrowed funds for liquidations

### Resources

- [Aave V3 Documentation](https://docs.aave.com/developers/core-contracts/pool)
- [Aave V3 Source Code](https://github.com/aave/aave-v3-core)
- [Understanding Liquidations](https://docs.aave.com/risk/asset-risk/risk-parameters#liquidation-threshold)
- [Foundry Book](https://book.getfoundry.sh/)

---

## Summary

In this exercise, you learned:

✅ How liquidations protect DeFi lending protocols  
✅ How to query user debt using variable debt tokens  
✅ The proper sequence of token transfers and approvals  
✅ How to call Aave's `liquidationCall` function  
✅ The relationship between health factors and liquidations  
✅ How liquidators profit from the liquidation bonus  

**Key Takeaways:**
- Liquidations are essential for protocol solvency
- Variable debt tokens represent borrowing obligations
- Proper token approvals are critical
- Liquidators are incentivized through bonuses
- Health factor determines liquidation eligibility

Congratulations on completing the liquidation exercise! You now understand one of the most important mechanisms in DeFi lending protocols. Practice building more advanced liquidation bots and explore profitability strategies to deepen your knowledge.

---

**Exercise Files:**
- Solution: `foundry/src/solutions/Liquidate.sol`
- Test: `foundry/test/Liquidate.test.sol`
- Exercise: `foundry/src/exercises/Liquidate.sol`
