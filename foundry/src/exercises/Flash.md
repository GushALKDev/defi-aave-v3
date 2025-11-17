# Flash Loan

## Concept

A flash loan is an uncollateralized loan that must be repaid within the same transaction. If the loan is not fully repaid (including the fee), the entire transaction reverts.

## Execution Flow

[`Pool.flashLoanSimple`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/pool/Pool.sol#L413-L430)

```
Pool.flashLoanSimple
└── FlashLoanLogic.executeFlashLoanSimple
    ├── IAToken.transferUnderlyingTo          // 1. Transfer borrowed tokens
    ├── IFlashLoanSimpleReceiver.executeOperation  // 2. Callback to receiver contract
    └── _handleFlashLoanRepayment             // 3. Recover loan + fee
        └── IERC20.safeTransferFrom
```

## `flashLoanSimple` Parameters

[`Pool.flashLoanSimple`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/pool/Pool.sol#L413-L430)

```solidity
function flashLoanSimple(
    address receiverAddress,  // Contract that receives the loan
    address asset,            // Token to borrow
    uint256 amount,           // Amount to borrow
    bytes calldata params,    // Additional data for the callback
    uint16 referralCode       // Referral code (usually 0)
) external
```

### receiverAddress
Address of the contract that:
- Will receive the borrowed tokens
- Must implement `IFlashLoanSimpleReceiver.executeOperation`
- Must have approval for the pool to recover `amount + fee`

### asset
ERC20 token to borrow (must be listed in Aave V3)

### amount
Amount of tokens to borrow

### params
Arbitrary data in bytes format passed to the `executeOperation` callback. Typically used to:
- Identify the original caller
- Pass parameters for arbitrage logic
- Encode instructions for complex operations

### referralCode
Optional referral code (usually `0`)

## `executeOperation` Callback

[`IFlashLoanSimpleReceiver.executeOperation`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/interfaces/IFlashLoanSimpleReceiver.sol)

The receiver contract MUST implement this function:

```solidity
function executeOperation(
    address asset,      // Borrowed token
    uint256 amount,     // Borrowed amount
    uint256 fee,        // Fee to pay
    address initiator,  // Who initiated the flash loan
    bytes calldata params  // Data passed from flashLoanSimple
) external returns (bool)
```

### Responsibilities

1. **Security validation**
   ```solidity
   require(msg.sender == address(pool), "Caller is not pool");
   require(initiator == address(this), "Initiator is not this contract");
   ```

2. **Business logic**
   - Execute arbitrage
   - Perform liquidation
   - Swaps across different DEXs
   - Any operation that generates profit

3. **Loan repayment**
   ```solidity
   // Contract must have amount + fee
   IERC20(asset).approve(address(pool), amount + fee);
   ```

4. **Return true**
   ```solidity
   return true;
   ```

## Fee Calculation

[`FlashLoanLogic.executeFlashLoanSimple`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/FlashLoanLogic.sol#L54-L152)

```
premium = flashloan fee percentage (configurable per reserve)
fee = amount * premium

Example:
- amount = 1,000,000 DAI
- premium = 0.05% (5 basis points)
- fee = 1,000,000 * 0.0005 = 500 DAI
```

The typical fee in Aave V3 is **0.05%** (5 basis points), but can vary depending on each reserve's configuration.

## Fee Distribution

[`_handleFlashLoanRepayment`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/FlashLoanLogic.sol#L180-L212)

```
total repayment = amount + fee

protocol fee = fee * protocol fee percentage
                (typically 0% for flash loans)

LP fee = fee - protocol fee
       = fee  (if protocol fee = 0%)
```

LPs (Liquidity Providers) receive most (or all) of the fee, which incentivizes liquidity provision.

## Validations

[`FlashLoanLogic.executeFlashLoanSimple`](https://github.com/aave-dao/aave-v3-origin/blob/5431379f8beb4d7128c84a81ced3917d856efa84/src/contracts/protocol/libraries/logic/FlashLoanLogic.sol#L54-L152)

### Before the loan

```solidity
// Reserve must be active
require(reserve.configuration.getActive(), "reserve not active");

// Flash loan must be enabled for this reserve
require(
    reserve.configuration.getFlashLoanEnabled(),
    "flashloan not enabled"
);

// Must have sufficient liquidity available
require(
    IERC20(asset).balanceOf(aToken) >= amount,
    "insufficient liquidity"
);
```

### After the callback

```solidity
// Pool must have received amount + fee
uint256 amountPlusPremium = amount + fee;
require(
    IERC20(asset).balanceOf(aToken) >= previousBalance + fee,
    "invalid flashloan repayment"
);
```

## Use Cases

### 1. Arbitrage
Buy low on one DEX and sell high on another within the same transaction

### 2. Liquidation
Borrow tokens to liquidate a position and repay the loan with the liquidation bonus

### 3. Debt Refinancing
Change the collateral of a position without needing initial capital

### 4. Complex Swaps
Perform multiple swaps that require temporary capital

## Implementation Example

```solidity
contract Flash {
    IPool public constant pool = IPool(POOL);

    function flash(address token, uint256 amount) public {
        // Initiate flash loan
        pool.flashLoanSimple({
            receiverAddress: address(this),
            asset: token,
            amount: amount,
            params: abi.encode(msg.sender),  // Pass caller
            referralCode: 0
        });
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    ) public returns (bool) {
        // Security validations
        require(msg.sender == address(pool), "not authorized");
        require(initiator == address(this), "invalid initiator");

        // Decode original caller
        address caller = abi.decode(params, (address));
        
        // Transfer fee from caller
        IERC20(asset).transferFrom(caller, address(this), fee);

        // ===== BUSINESS LOGIC HERE =====
        // - Arbitrage
        // - Liquidation
        // - Etc.
        // ===============================

        // Approve repayment of amount + fee
        IERC20(asset).approve(msg.sender, amount + fee);

        return true;
    }
}
```

## Gas Considerations

Flash loans consume significant gas:
- Initial token transfer
- Callback execution (varies by logic)
- Repayment transfer
- Liquidity index update

It's important to calculate if the expected profit covers:
```
profit > (fee + gas_cost)
```

## Security

### Reentrancy
Aave V3 is protected against reentrancy, but your callback must be secure:
```solidity
// Use OpenZeppelin's ReentrancyGuard
contract Flash is ReentrancyGuard {
    function executeOperation(...) 
        external 
        nonReentrant 
        returns (bool) 
    {
        // ...
    }
}
```

### Caller Validation
ALWAYS validate that the callback comes from the official Aave pool:
```solidity
require(msg.sender == address(pool), "unauthorized");
```

### Initiator Validation
Verify that the flash loan was initiated by your contract:
```solidity
require(initiator == address(this), "invalid initiator");
```

## Difference between `flashLoanSimple` and `flashLoan`

### flashLoanSimple
- Single asset
- More gas efficient
- Simpler callback
- **Use when you only need one token**

### flashLoan (multi-asset)
- Multiple assets in a single loan
- Receives arrays of assets, amounts, and fees
- More expensive in gas
- Use when you need several tokens simultaneously

## References

- [Aave V3 Pool.sol](https://github.com/aave-dao/aave-v3-origin/blob/main/src/contracts/protocol/pool/Pool.sol)
- [FlashLoanLogic.sol](https://github.com/aave-dao/aave-v3-origin/blob/main/src/contracts/protocol/libraries/logic/FlashLoanLogic.sol)
- [IFlashLoanSimpleReceiver.sol](https://github.com/aave-dao/aave-v3-origin/blob/main/src/contracts/interfaces/IFlashLoanSimpleReceiver.sol)
