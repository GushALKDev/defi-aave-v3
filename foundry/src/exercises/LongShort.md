# Long and Short Positions with Aave V3

## Concept

Long and short positions allow traders to speculate on asset price movements with leverage. In this implementation, we use Aave V3 as a lending protocol combined with DEX swap functionality to create leveraged positions.

### Long Position
- **Bet**: Asset price will increase
- **Strategy**: Borrow a stable token (e.g., DAI), swap it for the target asset (e.g., WETH), increasing exposure
- **Profit**: When the asset price rises relative to the borrowed token

```
Long Position Strategy Flow:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Initial   │    │   Borrow    │    │   Swap &    │
│ 1 WETH      │───▶│ 1000 DAI    │───▶│ Buy 0.4 WETH│
│ Collateral  │    │ (Stable)    │    │ (More Asset)│
└─────────────┘    └─────────────┘    └─────────────┘

Final Exposure: 1.4 WETH vs 1000 DAI debt
If WETH ↑ 10%: Profit = (1.4 × 10%) × WETH_Price - Interest
```

### Short Position  
- **Bet**: Asset price will decrease
- **Strategy**: Borrow the target asset (e.g., WETH), swap it for a stable token (e.g., DAI), betting the asset will fall
- **Profit**: When the asset price falls, allowing repayment with fewer stable tokens

```
Short Position Strategy Flow:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Initial   │    │   Borrow    │    │   Swap &    │
│ 1000 DAI    │───▶│ 0.3 WETH    │───▶│ Sell for    │
│ Collateral  │    │ (Target)    │    │ 900 DAI     │
└─────────────┘    └─────────────┘    └─────────────┘

Final Position: 1900 DAI vs 0.3 WETH debt
If WETH ↓ 10%: Repay with only ~810 DAI, profit ~90 DAI
```

### Long vs Short Comparison

```
Market Movement Impact:

WETH Price: $3000 → $3300 (+10%)
┌─────────────────┬─────────────────┬─────────────────┐
│   Position      │   Long WETH     │   Short WETH    │
├─────────────────┼─────────────────┼─────────────────┤
│ Initial Exposure│ 1.4 WETH        │ 1900 DAI        │
│                 │ 1000 DAI debt   │ 0.3 WETH debt   │
├─────────────────┼─────────────────┼─────────────────┤
│ Price Change    │ WETH ↑ $300     │ WETH ↑ $300     │
├─────────────────┼─────────────────┼─────────────────┤
│ Result          │ 📈 PROFIT       │ 📉 LOSS          │
│                 │ +$420 (1.4×$300)│ -$90 (0.3×$300) │
├─────────────────┼─────────────────┼─────────────────┤
│ Repayment Cost  │ Same 1000 DAI   │ More expensive  │
│                 │                 │ 0.3 WETH now    │
│                 │                 │ costs 990 DAI   │
└─────────────────┴─────────────────┴─────────────────┘

WETH Price: $3000 → $2700 (-10%)
┌─────────────────┬─────────────────┬─────────────────┐
│   Position      │   Long WETH     │   Short WETH    │
├─────────────────┼─────────────────┼─────────────────┤
│ Result          │ 📉 LOSS         │ 📈 PROFIT        │
│                 │ -$420 (1.4×$300)│ +$90 (0.3×$300) │
├─────────────────┼─────────────────┼─────────────────┤
│ Repayment Cost  │ Same 1000 DAI   │ Less expensive  │
│                 │                 │ 0.3 WETH now    │
│                 │                 │ costs 810 DAI   │
└─────────────────┴─────────────────┴─────────────────┘
```

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User (Caller) │◄───┤  LongShort      │◄───┤  Aave V3 Pool   │
│                 │    │   Contract      │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌─────────────────┐
                       │   DEX Router    │
                       │  (Uniswap V3)   │
                       └─────────────────┘
```

## Contract Structure

The `LongShort` contract inherits from both `Aave` and `Swap` libraries, providing:
- Access to Aave V3 lending functions
- Swap functionality via Uniswap V3
- Leveraged position management

**🚨 CRITICAL SECURITY WARNING**: This contract is for educational purposes only and contains serious security vulnerabilities:

1. **No Access Control**: Any caller can execute operations
2. **Token Custody Risk**: Contract temporarily holds borrowed tokens while user holds debt
3. **Delegation Abuse**: Any approved caller can borrow on behalf of the contract
4. **No Slippage Protection**: Vulnerable to MEV attacks and sandwich attacks
5. **Reentrancy Risks**: No protection against malicious callback attacks

**DO NOT USE IN PRODUCTION** without implementing proper:
- Access controls and authorization
- Atomic operations without token storage
- Slippage protection and MEV resistance
- Reentrancy guards and input validation
- Emergency pause mechanisms and time locks

## Understanding `onBehalfOf` in Aave V3

### What is `onBehalfOf`?

The `onBehalfOf` parameter in Aave V3 functions determines **who receives the benefits and liabilities** of the operation:

#### In `supply()`:
```solidity
pool.supply({
    asset: WETH,
    amount: 1e18,
    onBehalfOf: msg.sender,  // msg.sender receives aWETH tokens
    referralCode: 0
});
```
- **Who gets aTokens**: The `onBehalfOf` address receives the aTokens
- **Who can withdraw**: Only the aToken holder can withdraw the underlying asset

#### In `borrow()`:
```solidity  
pool.borrow({
    asset: DAI,
    amount: 1000e18,
    interestRateMode: 2,
    referralCode: 0,
    onBehalfOf: msg.sender  // msg.sender becomes the debtor
});
```
- **Who receives the debt**: The `onBehalfOf` address gets the variable debt token
- **Who receives borrowed tokens**: The tokens are sent to the calling contract
- **Who must repay**: Only the debtor (`onBehalfOf` address) can repay or have the debt repaid

#### In `repay()`:
```solidity
pool.repay({
    asset: DAI,
    amount: 1000e18,
    interestRateMode: 2,
    onBehalfOf: msg.sender  // Repaying msg.sender's debt
});
```
- **Whose debt is repaid**: The `onBehalfOf` address's debt is reduced
- **Who pays**: The calling contract provides the tokens for repayment

### Why Use `onBehalfOf` = `msg.sender`?

In our LongShort contract:
1. **User keeps control**: The user maintains ownership of aTokens and responsibility for debt
2. **Contract acts as facilitator**: The contract handles the complex operations but doesn't hold positions
3. **Separation of concerns**: User owns the position, contract provides the automation

## Task 1: Opening a Position

### Function Signature
```solidity
function open(OpenParams memory params) 
    public 
    returns (uint256 collateralAmountOut)
```

### Parameters Structure
```solidity
struct OpenParams {
    address collateralToken;     // Token to deposit as collateral
    uint256 collateralAmount;    // Amount of collateral to deposit
    address borrowToken;         // Token to borrow
    uint256 borrowAmount;        // Amount to borrow
    uint256 minHealthFactor;     // Minimum health factor after borrowing
    uint256 minSwapAmountOut;    // Minimum tokens expected from swap
    bytes swapData;              // Swap routing data
}
```

### Execution Flow

```
1. Validate Health Factor
        │
        ▼
2. Transfer Collateral from User
        │
        ▼
3. Supply Collateral to Aave
   (User receives aTokens)
        │
        ▼
4. Borrow Tokens from Aave
   (User gets debt, Contract gets tokens)
        │
        ▼
5. Validate Health Factor
        │
        ▼
6. Swap Borrowed → More Collateral
   (User receives swapped tokens)
```

### Detailed Step Analysis

#### Step 1.1: Health Factor Validation
```solidity
require(params.minHealthFactor > 1e18, "minHealthFactor too low");
```
**Purpose**: Ensure the minimum health factor is above 1.0 (liquidation threshold)
**Note**: Health factor < 1.0 means the position can be liquidated

#### Step 1.2: Collateral Transfer
```solidity
IERC20(params.collateralToken).transferFrom(
    msg.sender, 
    address(this), 
    params.collateralAmount
);
```
**Balance Tracking**:
- **User**: `-collateralAmount` of collateralToken
- **Contract**: `+collateralAmount` of collateralToken

#### Step 1.3: Supply to Aave
```solidity
IERC20(params.collateralToken).approve(address(pool), params.collateralAmount);
pool.supply({
    asset: params.collateralToken,
    amount: params.collateralAmount,
    onBehalfOf: msg.sender,  // User receives aTokens
    referralCode: 0
});
```

**onBehalfOf Explanation**:
- **User receives**: aTokens (e.g., aWETH) representing their supplied collateral
- **User can**: Withdraw the collateral later using their aTokens
- **Contract role**: Facilitates the supply but doesn't own the position

**Balance Tracking**:
- **User**: `+collateralAmount` of aTokens (e.g., aWETH)
- **Contract**: `-collateralAmount` of collateralToken (sent to Aave)
- **Aave Pool**: `+collateralAmount` of collateralToken

#### Step 1.4: Borrow from Aave
```solidity
pool.borrow({
    asset: params.borrowToken,
    amount: params.borrowAmount,
    interestRateMode: 2,  // Variable rate
    referralCode: 0,
    onBehalfOf: msg.sender  // User becomes the debtor
});
```

**onBehalfOf Explanation**:
- **User gets**: Variable debt tokens representing the loan obligation
- **Contract receives**: The actual borrowed tokens (e.g., DAI)
- **User must**: Either repay the debt or have someone repay on their behalf

**⚠️ CRITICAL SECURITY CONCERN**:
This mechanism creates a **dangerous separation** where:
- **User owns the debt** but **contract holds the borrowed tokens**
- **Contract can steal** the borrowed tokens and leave user with unpayable debt
- **Any caller can borrow** on behalf of the contract and drain funds

### Aave's Security Mechanisms

**1. Delegation Approval Required**:
```solidity
// User must explicitly approve the contract to borrow on their behalf
IVariableDebtToken debtToken = IVariableDebtToken(debtReserve.variableDebtTokenAddress);
debtToken.approveDelegation(address(target), type(uint256).max);
```

**2. Health Factor Enforcement**:
```solidity
// Aave checks user's health factor, not contract's
require(getHealthFactor(msg.sender) >= params.minHealthFactor, "health factor < min");
```

**3. Collateral Requirement**:
- User must have sufficient collateral (aTokens) to back the debt
- If health factor drops below 1.0, user's position can be liquidated

### Why This Design is Risky

```
Potential Attack Vector:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Malicious   │    │  Contract   │    │    User     │
│ Contract    │    │             │    │             │
│ Owner       │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘
       │                   │                   │
       │ 1. Call borrow()  │                   │
       │──────────────────▶│                   │
       │                   │ 2. Borrow tokens  │
       │                   │──────────────────▶│ (User gets debt)
       │                   │◄──────────────────│ (Contract gets tokens)
       │ 3. Steal tokens   │                   │
       │◄──────────────────│                   │
       │                   │                   │
Result: User has debt, malicious owner has tokens!
```

### Production Safety Measures

**1. Access Control**:
```solidity
mapping(address => bool) public authorizedUsers;

modifier onlyAuthorized() {
    require(authorizedUsers[msg.sender], "Not authorized");
    _;
}

function open(OpenParams memory params) public onlyAuthorized {
    // Implementation
}
```

**2. Atomic Operations**:
```solidity
function open(OpenParams memory params) public {
    // Borrow
    pool.borrow({...});
    
    // IMMEDIATELY use tokens - don't store them
    uint256 swapAmount = IERC20(params.borrowToken).balanceOf(address(this));
    _executeSwap(params.borrowToken, params.collateralToken, swapAmount);
    
    // Ensure no tokens left in contract
    require(IERC20(params.borrowToken).balanceOf(address(this)) == 0, "Tokens not used");
}
```

**3. Reentrancy Protection**:
```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LongShort is ReentrancyGuard {
    function open(OpenParams memory params) public nonReentrant {
        // Implementation
    }
}
```

**4. Time Locks and Multi-sig**:
```solidity
// For contract upgrades or admin functions
contract LongShort is Ownable {
    uint256 public constant TIMELOCK_DELAY = 24 hours;
    mapping(bytes32 => uint256) public queuedTransactions;
    
    function queueTransaction(bytes memory data) public onlyOwner {
        bytes32 txHash = keccak256(data);
        queuedTransactions[txHash] = block.timestamp + TIMELOCK_DELAY;
    }
}
```

### Educational vs Production Code

**This Educational Contract**:
```solidity
// ⚠️ UNSAFE: Any caller can borrow on behalf of contract
function open(OpenParams memory params) public {
    // No access control
    // No validation of caller
    // Tokens temporarily held in contract
}
```

**Production Contract Would Have**:
```solidity
// ✅ SAFE: Proper access controls and atomic operations
function open(OpenParams memory params) 
    public 
    onlyAuthorized 
    nonReentrant 
    validParams(params) 
{
    // Validate caller owns the collateral
    // Execute all operations atomically
    // Ensure no funds remain in contract
    // Emit events for transparency
}
```

**Balance Tracking**:
- **User**: `+borrowAmount` of debt tokens (e.g., variableDebtDAI)
- **Contract**: `+borrowAmount` of borrowToken (e.g., DAI) **⚠️ TEMPORARILY**

#### Step 1.5: Health Factor Check
```solidity
require(getHealthFactor(msg.sender) >= params.minHealthFactor, "health factor < min");
```
**Purpose**: Ensure the position is safe from liquidation

#### Step 1.6: Swap for Leverage
```solidity
IERC20(params.borrowToken).approve(address(router), params.borrowAmount);
uint256 swapAmountOut = Swap.swap({
    tokenIn: params.borrowToken,
    tokenOut: params.collateralToken,
    amountIn: params.borrowAmount,
    amountOutMin: params.minSwapAmountOut,
    receiver: msg.sender,  // User receives swapped tokens
    data: params.swapData
});
```

**Balance Tracking**:
- **Contract**: `-borrowAmount` of borrowToken (sent to DEX)
- **User**: `+swapAmountOut` of collateralToken (received from DEX)

### Example: Long WETH Position

**Scenario**: User believes WETH price will rise relative to DAI

**Initial State**:
```
User:     1 WETH
Contract: 0 WETH, 0 DAI
Aave:     Plenty of liquidity
```

**Parameters**:
```solidity
OpenParams({
    collateralToken: WETH,        // Deposit WETH as collateral
    collateralAmount: 1e18,       // 1 WETH
    borrowToken: DAI,             // Borrow DAI
    borrowAmount: 1000e18,        // 1000 DAI
    minHealthFactor: 1.5e18,      // 1.5 minimum health factor
    minSwapAmountOut: 1,          // Accept any amount (risky in production)
    swapData: abi.encode(fee)     // Uniswap V3 pool fee
})
```

**Step-by-Step Balance Changes**:

**After Step 1.2 (Transfer)**:
```
User:     0 WETH
Contract: 1 WETH, 0 DAI
```

**After Step 1.3 (Supply)**:
```
User:     1 aWETH, 0 WETH
Contract: 0 WETH, 0 DAI
Aave:     +1 WETH in pool
```

**After Step 1.4 (Borrow)**:
```
User:     1 aWETH, 1000 DAI debt
Contract: 0 WETH, 1000 DAI
Aave:     +1 WETH, -1000 DAI in pools
```

**After Step 1.6 (Swap)**:
```
User:     1 aWETH, ~0.4 WETH (from swap), 1000 DAI debt
Contract: 0 WETH, 0 DAI
DEX:      +1000 DAI, -0.4 WETH
```

**Final Position**:
- **Exposure**: ~1.4 WETH (1 aWETH + 0.4 WETH)
- **Debt**: 1000 DAI
- **Leverage**: ~1.4x (1.4 WETH exposure from 1 WETH initial capital)

## Task 2: Closing a Position

### Function Signature
```solidity
function close(CloseParams memory params)
    public
    returns (
        uint256 collateralWithdrawn,
        uint256 debtRepaidFromMsgSender, 
        uint256 borrowedLeftover
    )
```

### Parameters Structure
```solidity
struct CloseParams {
    address collateralToken;          // Collateral token to use for closing
    uint256 collateralAmount;         // Amount of collateral to swap
    uint256 maxCollateralToWithdraw;  // Max collateral to withdraw from Aave
    address borrowToken;              // Token that was borrowed
    uint256 maxDebtToRepay;          // Maximum debt to repay
    uint256 minSwapAmountOut;        // Minimum tokens expected from swap
    bytes swapData;                  // Swap routing data
}
```

### Execution Flow

```
1. Transfer Collateral from User
        │
        ▼
2. Swap Collateral → Borrowed Token
        │
        ▼
3. Repay Debt to Aave
   (If insufficient, get more from User)
        │
        ▼
4. Withdraw Collateral from Aave
   (Transfer aTokens from User)
        │
        ▼
5. Return Leftover Profit to User
```

### Detailed Step Analysis

#### Step 2.1: Transfer Collateral
```solidity
IERC20(params.collateralToken).transferFrom(
    msg.sender, 
    address(this), 
    params.collateralAmount
);
```

**Balance Tracking**:
- **User**: `-collateralAmount` of collateralToken
- **Contract**: `+collateralAmount` of collateralToken

#### Step 2.2: Swap for Repayment
```solidity
IERC20(params.collateralToken).approve(address(router), params.collateralAmount);
uint256 swapAmountOut = Swap.swap({
    tokenIn: params.collateralToken,
    tokenOut: params.borrowToken,
    amountIn: params.collateralAmount,
    amountOutMin: params.minSwapAmountOut,
    receiver: address(this),  // Contract receives swapped tokens
    data: params.swapData
});
```

**Balance Tracking**:
- **Contract**: `-collateralAmount` of collateralToken, `+swapAmountOut` of borrowToken

#### Step 2.3: Debt Repayment Logic
```solidity
uint256 currentDebt = Aave.getVariableDebt(params.borrowToken, msg.sender);
uint256 debtToRepay = Math.min(currentDebt, params.maxDebtToRepay);

uint256 repayAmount = 0;
if (debtToRepay > swapAmountOut) {
    repayAmount = debtToRepay - swapAmountOut;
    IERC20(params.borrowToken).transferFrom(msg.sender, address(this), repayAmount);
}
```

**Scenarios**:

**Scenario A: Profitable Position (swapAmountOut ≥ debtToRepay)**
- Swap provides enough tokens to repay debt
- `repayAmount = 0` (no additional transfer needed)
- User will receive profit

**Scenario B: Loss Position (swapAmountOut < debtToRepay)**  
- Swap doesn't provide enough tokens
- User must provide `repayAmount = debtToRepay - swapAmountOut`
- User covers the loss

**Balance Tracking** (Loss scenario):
- **User**: `-repayAmount` of borrowToken  
- **Contract**: `+repayAmount` of borrowToken

#### Step 2.4: Repay to Aave
```solidity
IERC20(params.borrowToken).approve(address(pool), debtToRepay);
pool.repay({
    asset: params.borrowToken,
    amount: debtToRepay,
    interestRateMode: 2,
    onBehalfOf: msg.sender  // Repaying user's debt
});
```

**onBehalfOf Explanation**:
- **User's debt**: Reduced by `debtToRepay` amount
- **User's debt tokens**: Burned accordingly
- **Contract provides**: The tokens for repayment

**Balance Tracking**:
- **User**: `-debtToRepay` of debt tokens
- **Contract**: `-debtToRepay` of borrowToken (sent to Aave)

#### Step 2.5: Withdraw Collateral
```solidity
address aTokenAddress = Aave.getATokenAddress(params.collateralToken);
uint256 aTokenBalance = IERC20(aTokenAddress).balanceOf(msg.sender);
uint256 amountToWithdraw = Math.min(aTokenBalance, params.maxCollateralToWithdraw);

IERC20(aTokenAddress).transferFrom(msg.sender, address(this), amountToWithdraw);

uint256 withdrawn = pool.withdraw({
    asset: params.collateralToken,
    amount: amountToWithdraw,
    to: msg.sender  // User receives the withdrawn collateral
});
```

**Process**:
1. **aToken Transfer**: User transfers aTokens to contract
2. **Withdraw**: Contract withdraws underlying tokens from Aave  
3. **Delivery**: Aave sends underlying tokens to user

**Balance Tracking**:
- **User**: `-amountToWithdraw` of aTokens, `+withdrawn` of collateralToken
- **Contract**: `+amountToWithdraw` of aTokens (temporarily)
- **Aave**: `-withdrawn` of collateralToken (sent to user)

#### Step 2.6: Return Profit
```solidity
uint256 balanceBorrowToken = IERC20(params.borrowToken).balanceOf(address(this));
if (balanceBorrowToken > 0) {
    IERC20(params.borrowToken).transfer(msg.sender, balanceBorrowToken);
}
```

**Balance Tracking** (if profit exists):
- **Contract**: `-balanceBorrowToken` of borrowToken
- **User**: `+balanceBorrowToken` of borrowToken (profit!)

### Example: Closing Long WETH Position

**Scenario**: User wants to close their leveraged WETH position

**Current State** (after some time and price movement):
```
User:     1 aWETH, 0.4 WETH, 1000 DAI debt
WETH Price: $3,000 → $3,300 (10% increase)
```

**Parameters**:
```solidity
CloseParams({
    collateralToken: WETH,
    collateralAmount: 0.4e18,      // Use the 0.4 WETH from opening
    maxCollateralToWithdraw: type(uint256).max,  // Withdraw all aTokens
    borrowToken: DAI,
    maxDebtToRepay: type(uint256).max,          // Repay all debt
    minSwapAmountOut: 1,           // Accept any amount
    swapData: abi.encode(fee)
})
```

**Step-by-Step Balance Changes**:

**After Step 2.1 (Transfer)**:
```
User:     1 aWETH, 0 WETH, 1000 DAI debt
Contract: 0.4 WETH, 0 DAI
```

**After Step 2.2 (Swap)** - assuming 0.4 WETH → 1,200 DAI:
```
User:     1 aWETH, 0 WETH, 1000 DAI debt  
Contract: 0 WETH, 1,200 DAI
```

**After Step 2.4 (Repay)** - repay 1000 DAI debt:
```
User:     1 aWETH, 0 WETH, 0 DAI debt
Contract: 0 WETH, 200 DAI (profit!)
```

**After Step 2.5 (Withdraw)** - withdraw 1 WETH using aWETH:
```
User:     0 aWETH, 1 WETH, 0 DAI debt
Contract: 0 WETH, 200 DAI
```

**After Step 2.6 (Return Profit)**:
```
User:     0 aWETH, 1 WETH, 200 DAI (profit!)
Contract: 0 WETH, 0 DAI
```

**Final Result**:
- **Initial**: 1 WETH
- **Final**: 1 WETH + 200 DAI profit
- **Profit**: 200 DAI from 10% WETH price increase with leverage

## Visual Fund Flow Diagram

### Opening a Long Position

```
Initial State:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │    │  Contract   │    │    Aave     │
│  1 WETH     │    │   Empty     │    │  Liquidity  │
│             │    │             │    │   Pools     │
└─────────────┘    └─────────────┘    └─────────────┘

Step 1-2: Transfer Collateral
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │────│  Contract   │    │    Aave     │
│   0 WETH    │ 1W │  1 WETH     │    │  Liquidity  │
│             │────│             │    │   Pools     │
└─────────────┘    └─────────────┘    └─────────────┘

Step 3: Supply to Aave (onBehalfOf: User)
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │    │  Contract   │────│    Aave     │
│  1 aWETH    │    │   Empty     │ 1W │+1 WETH Pool │
│             │    │             │────│             │
└─────────────┘    └─────────────┘    └─────────────┘

Step 4: Borrow from Aave (onBehalfOf: User)
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │    │  Contract   │────│    Aave     │
│  1 aWETH    │    │ 1000 DAI    │1kD │-1000 DAI    │
│ 1000D debt  │    │             │────│  Pool       │
└─────────────┘    └─────────────┘    └─────────────┘

Step 6: Swap DAI → WETH (User receives)
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │────│  Contract   │    │     DEX     │
│  1 aWETH    │0.4W│   Empty     │────│ 1000D→0.4W  │
│  0.4 WETH   │────│             │1kD │             │
│ 1000D debt  │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘

Final Long Position: 1.4 WETH exposure, 1000 DAI debt
```

### Closing the Position (Profitable)

```
Position State:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │    │  Contract   │    │    Aave     │
│  1 aWETH    │    │   Empty     │    │  1 WETH     │
│  0.4 WETH   │    │             │    │ Collateral  │
│ 1000D debt  │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘

Step 1: Transfer Collateral to Close
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │────│  Contract   │    │    Aave     │
│  1 aWETH    │0.4W│  0.4 WETH   │    │  1 WETH     │
│   0 WETH    │────│             │    │ Collateral  │
│ 1000D debt  │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘

Step 2: Swap WETH → DAI (Price ↑10%)
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │    │  Contract   │────│     DEX     │
│  1 aWETH    │    │ 1200 DAI    │0.4W│ 0.4W→1200D  │
│   0 WETH    │    │             │────│             │
│ 1000D debt  │    │             │1.2kD│            │
└─────────────┘    └─────────────┘    └─────────────┘

Step 4: Repay Debt (onBehalfOf: User)
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │    │  Contract   │────│    Aave     │
│  1 aWETH    │    │  200 DAI    │1kD │ Debt Repaid │
│   0 WETH    │    │             │────│             │
│   0 debt    │    │             │    │             │
└─────────────┘    └─────────────┘    └─────────────┘

Step 5: Withdraw Collateral (User transfers aTokens)
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    User     │────│  Contract   │────│    Aave     │
│  0 aWETH    │1aW │ 1 aWETH     │1aW │ Send 1 WETH │
│  1 WETH     │────│  200 DAI    │────│   to User   │
│   0 debt    │ 1W │             │ 1W │             │
└─────────────┘    └─────────────┘    └─────────────┘

Step 6: Return Profit
┌─────────────┐    ┌─────────────┐
│    User     │────│  Contract   │
│  0 aWETH    │200D│   Empty     │
│  1 WETH     │────│             │
│  200 DAI    │    │             │
│   0 debt    │    │             │
└─────────────┘    └─────────────┘

Final Result: 1 WETH + 200 DAI profit from leverage!
```

## Balance Tracking Summary

### Long WETH Example

| Phase | User WETH | User aWETH | User DAI | User Debt | Contract WETH | Contract DAI |
|-------|-----------|------------|----------|-----------|---------------|--------------|
| Initial | 1.0 | 0 | 0 | 0 | 0 | 0 |
| After Transfer | 0 | 0 | 0 | 0 | 1.0 | 0 |
| After Supply | 0 | 1.0 | 0 | 0 | 0 | 0 |
| After Borrow | 0 | 1.0 | 0 | 1000 | 0 | 1000 |
| After Swap | 0.4 | 1.0 | 0 | 1000 | 0 | 0 |
| **Position Open** | **0.4** | **1.0** | **0** | **1000** | **0** | **0** |

**Closing (Profitable scenario - WETH price +10%)**

| Phase | User WETH | User aWETH | User DAI | User Debt | Contract WETH | Contract DAI |
|-------|-----------|------------|----------|-----------|---------------|--------------|
| Position | 0.4 | 1.0 | 0 | 1000 | 0 | 0 |
| After Transfer | 0 | 1.0 | 0 | 1000 | 0.4 | 0 |
| After Swap | 0 | 1.0 | 0 | 1000 | 0 | 1200 |
| After Repay | 0 | 1.0 | 0 | 0 | 0 | 200 |
| After Withdraw | 1.0 | 0 | 0 | 0 | 0 | 200 |
| After Profit | 1.0 | 0 | 200 | 0 | 0 | 0 |
| **Final** | **1.0** | **0** | **200** | **0** | **0** | **0** |

**Net Result**: Started with 1 WETH, ended with 1 WETH + 200 DAI profit!

## Risk Considerations

### 1. Health Factor Risk
```
Health Factor = (Collateral Value × Liquidation Threshold) / Debt Value
```
- **Safe**: Health Factor > 1.2
- **Warning**: Health Factor 1.0 - 1.2  
- **Liquidation**: Health Factor < 1.0

### 2. Price Risk
- **Long positions**: Lose money if asset price falls relative to borrowed token
- **Short positions**: Lose money if asset price rises relative to borrowed token

### 3. Slippage Risk
- DEX swaps may receive fewer tokens than expected
- Use appropriate `minSwapAmountOut` parameters

### 4. Interest Rate Risk
- Borrowed amounts accrue interest over time
- Variable rates can change based on utilization

### 5. Smart Contract Risk
- **Educational code**: Not audited for production use
- **Approval risks**: Contract has broad permissions
- **Front-running**: Transactions can be front-run in public mempools

## Test Examples

The test file demonstrates both long and short scenarios:

### Long WETH Test
```solidity
// Open: Deposit 1 WETH, borrow 1000 DAI, swap DAI → WETH
target.open(LongShort.OpenParams({
    collateralToken: WETH,
    collateralAmount: 1e18,      // 1 WETH collateral
    borrowToken: DAI, 
    borrowAmount: 1000 * 1e18,   // 1000 DAI borrowed
    minHealthFactor: 1.5 * 1e18, // 1.5 minimum health factor
    minSwapAmountOut: 1,
    swapData: abi.encode(UNISWAP_V3_POOL_FEE_DAI_WETH)
}));
```

### Short WETH Test  
```solidity
// Open: Deposit 1000 DAI, borrow 0.1 WETH, swap WETH → DAI
target.open(LongShort.OpenParams({
    collateralToken: DAI,
    collateralAmount: 1000 * 1e18,  // 1000 DAI collateral
    borrowToken: WETH,
    borrowAmount: 0.1 * 1e18,       // 0.1 WETH borrowed  
    minHealthFactor: 1.5 * 1e18,
    minSwapAmountOut: 1,
    swapData: abi.encode(UNISWAP_V3_POOL_FEE_DAI_WETH)
}));
```

## Running Tests

```bash
# Run all LongShort tests
forge test --fork-url $FORK_URL --fork-block-number $FORK_BLOCK_NUM --match-path test/LongShort.test.sol -vvv

# Run specific test
forge test --fork-url $FORK_URL --fork-block-number $FORK_BLOCK_NUM --match-test test_long_weth -vvv
```

## Key Takeaways

1. **Leverage Amplifies Returns**: Small price movements result in larger profits/losses
2. **Health Factor Management**: Always maintain a safe health factor to avoid liquidation
3. **onBehalfOf Mechanics**: Understand who owns what in each Aave operation
4. **Swap Slippage**: Price movements during execution can affect profitability
5. **Interest Accumulation**: Borrowed amounts grow over time
6. **Risk Management**: Never risk more than you can afford to lose

## Next Steps

To deepen your understanding:
1. Implement position monitoring and automatic rebalancing
2. Add slippage protection and MEV resistance  
3. Create a frontend interface for position management
4. Study real-world leveraged trading protocols like Compound Leverage or Aave Flash Loans
5. Learn about advanced strategies like delta-neutral positions

---

**⚠️ Educational Notice**: This contract is for learning purposes only. Production implementations require proper access controls, slippage protection, MEV resistance, and comprehensive testing.