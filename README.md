# Impermanent Cover - Insurance Protocol

A parametric insurance protocol built on the Stacks blockchain to protect liquidity providers against impermanent loss in DeFi pools.

## Overview

Impermanent Cover provides insurance coverage for LP (Liquidity Provider) tokens against impermanent loss. The protocol uses parametric insurance principles, meaning payouts are automatically triggered based on measurable price ratio changes rather than manual claim assessment.

## Key Features

- **Parametric Insurance**: Automated payouts based on price oracle data
- **Flexible Coverage**: Coverage periods from 1 day to 1 year
- **Multiple Trading Pairs**: Support for various LP token pairs (STX-USDC, STX-BTC, etc.)
- **Risk-Based Pricing**: Premium calculation based on coverage amount, period, and historical volatility
- **Transparent Claims**: Automated claim processing with clear IL calculations
- **Oracle Integration**: Real-time price feeds for accurate loss calculation

## How It Works

### 1. Policy Purchase
Users purchase insurance policies by specifying:
- LP token amount to insure
- Trading pair (e.g., "STX-USDC")
- Coverage amount (up to 200% of LP value)
- Coverage period (1 day to 1 year)

### 2. Premium Calculation
Premium = `(LP Amount × Base Rate × Period Multiplier × Coverage Ratio) / 100,000,000`

Where:
- Base Rate: 0.5% (50 basis points)
- Period Multiplier: Based on coverage duration
- Coverage Ratio: Percentage of LP value to cover

### 3. Impermanent Loss Monitoring
The protocol tracks:
- Initial price ratio when policy is created
- Current price ratio via oracles
- Calculated impermanent loss percentage

### 4. Claims Processing
- Claims can be filed after 1 day waiting period
- Must be filed before policy expiration
- Automatic payout if IL > 1%
- Payout = min(Calculated Loss, Coverage Amount)

## Smart Contract Functions

### Core Functions

#### `purchase-policy`
```clarity
(purchase-policy lp-token-amount pool-pair coverage-amount coverage-period)
```
Purchase insurance coverage for LP tokens.

**Parameters:**
- `lp-token-amount`: Amount of LP tokens to insure (uint)
- `pool-pair`: Trading pair identifier (string-ascii 64)
- `coverage-amount`: Maximum payout amount (uint)
- `coverage-period`: Coverage duration in blocks (uint)

**Returns:** Policy ID (uint)

#### `file-claim`
```clarity
(file-claim policy-id)
```
File a claim for impermanent loss compensation.

**Parameters:**
- `policy-id`: ID of the policy to claim against (uint)

**Returns:** Claim payout amount (uint)

#### `update-price`
```clarity
(update-price pool-pair new-price-ratio)
```
Update price ratio for a trading pair (oracle function).

**Parameters:**
- `pool-pair`: Trading pair identifier (string-ascii 64)
- `new-price-ratio`: New price ratio scaled by 1e6 (uint)

### Read-Only Functions

#### `get-policy`
```clarity
(get-policy policy-id)
```
Retrieve policy details by ID.

#### `calculate-premium`
```clarity
(calculate-premium lp-amount coverage-period coverage-amount)
```
Calculate insurance premium for given parameters.

#### `calculate-impermanent-loss`
```clarity
(calculate-impermanent-loss initial-ratio current-ratio)
```
Calculate impermanent loss percentage.

## Usage Examples

### 1. Purchase Insurance Policy
```clarity
;; Insure 1000 STX-USDC LP tokens for 30 days with 150% coverage
(contract-call? .impermanent-cover purchase-policy 
  u1000 
  "STX-USDC" 
  u1500 
  u4320) ;; 30 days in blocks
```

### 2. File a Claim
```clarity
;; File claim for policy ID 1
(contract-call? .impermanent-cover file-claim u1)
```

### 3. Check Policy Status
```clarity
;; Get policy details
(contract-call? .impermanent-cover get-policy u1)
```

## Oracle Integration

### Setting Up Price Oracles
```clarity
;; Set oracle for STX-USDC pair (owner only)
(contract-call? .impermanent-cover set-oracle 
  "STX-USDC" 
  'SP1234...ORACLE-ADDRESS)
```

### Updating Prices
```clarity
;; Update STX-USDC price ratio to 1.5 (oracle only)
(contract-call? .impermanent-cover update-price 
  "STX-USDC" 
  u1500000) ;; 1.5 * 1e6
```

## Economic Model

### Fee Structure
- Protocol fee: 3% of premiums (configurable by owner)
- Base insurance rate: 0.5% of LP value
- No claim processing fees

### Coverage Limits
- Minimum coverage period: 1 day (144 blocks)
- Maximum coverage period: 1 year (52,560 blocks)
- Maximum coverage amount: 200% of LP token value

### Risk Management
- Waiting period: 1 day before claims can be filed
- Minimum IL threshold: 1% for claim processing
- Policy status tracking prevents double claims

## Security Features

### Access Control
- Owner-only administrative functions
- Oracle-only price update permissions
- Policy holder-only claim filing

### Validation
- Input parameter validation
- Policy status verification
- Sufficient fund checks
- Time-based restrictions

### Emergency Features
- Emergency withdrawal function for contract owner
- Fund contract function for liquidity management

## Deployment

### Prerequisites
- Stacks blockchain testnet/mainnet access
- Clarinet for local testing
- STX tokens for deployment

### Deployment Steps
1. Deploy contract to Stacks blockchain
2. Set up price oracles for supported trading pairs
3. Fund contract with initial liquidity
4. Configure protocol parameters

### Testing
```bash
# Run tests with Clarinet
clarinet test

# Check contract syntax
clarinet check
```

## Risk Considerations

### For Users
- Oracle dependency for price feeds
- Contract solvency risk
- Time-based claim restrictions
- Premium costs vs. potential losses

### For Protocol
- Oracle manipulation attacks
- Insufficient liquidity for claims
- Model risk in IL calculations
- Smart contract bugs

## Supported Trading Pairs

Currently configured pairs:
- STX-USDC
- STX-BTC

Additional pairs can be added by the contract owner.

## Error Codes

- `u100`: Owner only function
- `u101`: Not found
- `u102`: Insufficient funds
- `u103`: Policy expired
- `u104`: Policy still active
- `u105`: Invalid amount
- `u106`: Already exists
- `u107`: Unauthorized
- `u108`: Invalid parameters
- `u109`: Claim too early
- `u110`: Claim too late
