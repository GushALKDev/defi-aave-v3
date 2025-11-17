# Detailed Explanation: Decimal Conversion in Borrow

## Exercise Context

In the Aave V3 Borrow exercise, we need to calculate the maximum amount of tokens we can borrow based on:
- The USD value available to borrow (`availableBorrowsBase`)
- The token price in USD (`assetPrice`)

The main challenge is that these values come with **the same decimal precision (8 decimals)**, which simplifies the calculation significantly.

## Values and Their Decimals

### 1. `availableBorrowsBase` - 8 decimals
```solidity
(, , uint256 availableBorrowsBase, , , ) = pool.getUserAccountData(address(this));
```

This value represents **how many USD you can borrow** and comes with **8 decimals of precision**.

**Example:**
```
availableBorrowsBase = 249196203614
```

To convert to real USD:
```
Real USD = 249196203614 / 10^8
         = 2491.96203614 USD
```

**Why 8 decimals?** Aave V3 uses 8 decimals for its base currency unit (USD) to match the precision of Chainlink price feeds. This is explicitly defined in the `IPriceOracleGetter` interface:
```solidity
/**
 * @notice Returns the base currency unit
 * @dev 1 ether for ETH, 1e8 for USD.
 * @return Returns the base currency unit.
 */
function BASE_CURRENCY_UNIT() external view returns (uint256);
```

### 2. `assetPrice` - 8 decimals
```solidity
uint256 assetPrice = oracle.getAssetPrice(token);
```

This value represents the **price of one token in USD** and comes with **8 decimals of precision**.

**Example (USDC):**
```
assetPrice = 100015234
```

To convert to real USD:
```
Real USD per USDC = 100015234 / 10^8
                  = 1.00015234 USD per USDC
```

**Important:** This is the **price** of USDC in USD (how many USD one USDC costs), not the amount of USDC. The price has 8 decimals from the oracle, regardless of USDC having 6 decimals as a token. The token decimals (6 for USDC) are used later to scale the final result.

**Why 8 decimals?** Chainlink oracles return prices with 8 decimals of precision. Aave V3 uses Chainlink as its price feed provider and maintains consistency by using 8 decimals throughout.

### 3. `decimals` - Token decimals
```solidity
uint8 decimals = IERC20Metadata(token).decimals();
```

Each ERC20 token has its own number of decimals. The most common:
- USDC: 6 decimals
- DAI: 18 decimals
- WBTC: 8 decimals
- WETH: 18 decimals

## The Conversion Formula

```solidity
uint256 maxBorrow = (availableBorrowsBase * (10 ** decimals)) / assetPrice;
```

### Why does this formula work?

The key insight is that **both `availableBorrowsBase` and `assetPrice` have 8 decimals**, so they cancel each other out perfectly. Let's analyze dimensionally:

```solidity
maxBorrow = (availableBorrowsBase * 10^decimals) / assetPrice
```

Substituting units:

```
maxBorrow = (USD * 10^8 * 10^decimals) / (price in USD * 10^8)
```

The 10^8 factors cancel out:

```
maxBorrow = (USD * 10^decimals) / (price in USD)
          = (USD / price in USD) * 10^decimals
          = token quantity * 10^decimals
```

**This leaves us with the token amount scaled to its native decimals!**

### Breaking it down step by step

1. **Start with USD available** (8 decimals): `availableBorrowsBase`
2. **Multiply by token decimals**: `availableBorrowsBase * 10^decimals`
   - This scales up our calculation to prepare for the token's precision
3. **Divide by price** (8 decimals): `/ assetPrice`
   - The 8-decimal factors cancel
   - We get the token amount in its native base units

## Complete Numerical Example (USDC)

Test data:
```
availableBorrowsBase = 250000000000        // USD with 8 decimals
assetPrice = 100015234                      // USD per USDC with 8 decimals
decimals = 6                                // USDC has 6 decimals
```

### Step 1: Interpret the USD available
```
Real USD available = 250000000000 / 10^8
                   = 2500 USD
```

### Step 2: Interpret the USDC price
```
USDC price = 100015234 / 10^8
           = 1.00015234 USD per USDC
```

### Step 3: Calculate using the formula
```
maxBorrow = (250000000000 * 10^6) / 100015234
          = 250000000000 * 10^6 / 100015234
          = 2499619106 (in base units with 6 decimals)
```

### Step 4: Convert to readable USDC
```
maxBorrow in USDC = 2499619106 / 10^6
                  = 2499.619106 USDC
```

### Step 5: Verify the calculation
```
USD available / USDC price = 2500 / 1.00015234
                           ≈ 2499.62 USDC
```

✅ **Perfect match!**

## Detailed Dimensional Analysis

### Unit notation

Let:
- `[USD_8]` = USD with 8 decimals of precision
- `[token_n]` = token with n decimals

### Input values

```
availableBorrowsBase: [USD_8]
assetPrice: [USD_8 per token]
decimals: number of decimals for the token (n)
```

### Expanded formula

```solidity
maxBorrow = (availableBorrowsBase * 10^decimals) / assetPrice
```

**Dimensionally:**

```
[token_n] = ([USD_8] * 10^n) / [USD_8 per token]
```

**Simplifying:**

```
[token_n] = [USD_8] * 10^n * [token per USD_8]
```

The [USD_8] factor cancels out completely:

```
[token_n] = 10^n * [token]
```

**This gives us the token in its native base units (10^n)!**

### The beauty of matching decimals

Since both `availableBorrowsBase` and `assetPrice` use **8 decimals from the oracle system**, they cancel perfectly:

```
(USD with 8 decimals) / (price with 8 decimals) = token quantity
```

Then we simply scale by `10^decimals` to get the token in its base units.

## Why not simply use `availableBorrowsBase / assetPrice`?

If we did:
```solidity
uint256 wrong = availableBorrowsBase / assetPrice;
```

**Dimensionally:**
```
wrong = [USD_8] / [USD_8 per token]
      = [USD_8] * [token per USD_8]
      = token (but in what units?)
```

This would give us the token but **without proper scaling**. We'd get a result that represents:
- 1 token = 1 unit (instead of 10^6 for USDC or 10^18 for DAI)
- For USDC this would be off by a factor of 10^6!
- For DAI this would be off by a factor of 10^18!

The multiplication by `10^decimals` is essential to get the correct base units for each token.

## Practical Cases: Different Token Decimals

### USDC (6 decimals)

```solidity
availableBorrowsBase = 100000000000    // 1000 USD (8 decimals)
assetPrice = 100000000                 // 1 USD per USDC (8 decimals)
decimals = 6

maxBorrow = (100000000000 * 10^6) / 100000000
          = 1000000000 * 10^6
          = 1000 * 10^6 USDC (in base units)
          = 1000 USDC (readable)
```

### WETH (18 decimals)

```solidity
availableBorrowsBase = 100000000000    // 1000 USD (8 decimals)
assetPrice = 309560501385              // 3095.60501385 USD per WETH (8 decimals)
decimals = 18

maxBorrow = (100000000000 * 10^18) / 309560501385
          = 100000000000000000000000000000 / 309560501385
          = 323050938430283364 (in wei, WETH base units with 18 decimals)
```

Converting to readable WETH:
```
maxBorrow in WETH = 323050938430283364 / 10^18
                  ≈ 0.323050938430283364 WETH
```

Verification:
```
USD available / WETH price = 1000 / 3095.60501385
                           ≈ 0.323 WETH ✓
```

### DAI (18 decimals)

```solidity
availableBorrowsBase = 100000000000    // 1000 USD (8 decimals)
assetPrice = 100000000                 // 1 USD per DAI (8 decimals)
decimals = 18

maxBorrow = (100000000000 * 10^18) / 100000000
          = 1000000000 * 10^18
          = 1000 * 10^18 DAI (in base units)
          = 1000 DAI (readable)
```

All three examples show how the same formula works correctly for tokens with different decimals (6, 18) and vastly different prices ($1 vs $3095).

## Conversion Summary

### Input
- `availableBorrowsBase`: Available USD with **8 decimals** (matches Chainlink oracle precision)
- `assetPrice`: Token price in USD with **8 decimals** (from Chainlink oracle)
- `decimals`: Specific token decimals

### Process
1. **Multiply** available USD by `10^decimals` to prepare for token scaling
2. **Divide by price** - the 8-decimal factors cancel out perfectly
3. Result: token amount in its native base units

### Output
- `maxBorrow`: Maximum token amount in **base units** (scaled by token decimals)

### Converting to readable units
```solidity
maxBorrowReadable = maxBorrow / (10 ** decimals)
```

## Conclusion

The formula:
```solidity
uint256 maxBorrow = (availableBorrowsBase * (10 ** decimals)) / assetPrice;
```

Is **mathematically elegant and correct** because:

1. ✅ Both `availableBorrowsBase` and `assetPrice` use **8 decimals** (from the oracle system)
2. ✅ The 8-decimal factors **cancel each other out perfectly**
3. ✅ Multiplying by `10^decimals` scales the result to the **token's native base units**
4. ✅ It's **generic for any token** regardless of its decimals (18, 6, 8, etc.)
5. ✅ Maintains **precision** by working with integers in Solidity

The key insight is that **Aave V3 uses 8 decimals throughout its USD accounting** to match Chainlink's 8-decimal price feeds. This creates perfect symmetry:

```
(USD with 8 decimals) / (price with 8 decimals) = token quantity
```

Then we simply scale by the token's decimals to get the proper base units. Simple, elegant, and correct!
