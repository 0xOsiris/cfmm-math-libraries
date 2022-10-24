```solidity
 ________  ________ _____ ______   _____ ______           _____ ______   ________  _________  ___  ___     
|\   ____\|\  _____\\   _ \  _   \|\   _ \  _   \        |\   _ \  _   \|\   __  \|\___   ___\\  \|\  \    
\ \  \___|\ \  \__/\ \  \\\__\ \  \ \  \\\__\ \  \       \ \  \\\__\ \  \ \  \|\  \|___ \  \_\ \  \\\  \   
 \ \  \    \ \   __\\ \  \\|__| \  \ \  \\|__| \  \       \ \  \\|__| \  \ \   __  \   \ \  \ \ \   __  \  
  \ \  \____\ \  \_| \ \  \    \ \  \ \  \    \ \  \       \ \  \    \ \  \ \  \ \  \   \ \  \ \ \  \ \  \ 
   \ \_______\ \__\   \ \__\    \ \__\ \__\    \ \__\       \ \__\    \ \__\ \__\ \__\   \ \__\ \ \__\ \__\
    \|_______|\|__|    \|__|     \|__|\|__|     \|__|        \|__|     \|__|\|__|\|__|    \|__|  \|__|\|__|
   
```
# Overview
CFMM Math Solidity library & contract for price simulation, fixed point conversion, and swap simulation on v2/v3 pools. The idea behind CFMM math is to provide an out of the box solidity tool suite that allows anyone to simulate, quote, compare, and convert v2/v3 prices seemlessly in a standardized fixed point representation. 

This repository is still very much so a work in progress. The overall goal is to provide a solidity tool suite that acts as an abstraction layer on top of the major dex variants cfmm internal math libraries to allow very simple price comparison, simulation, and conversion by using a standardized fixed point framework. If you have any suggestions or issues, feel free to open an issue and I'll get back to you. Further, collaboration is more than welcome, so feel free to PR :)
# Installation
To install as an npm package run:
```shell
npm i cfmm-math-libraries
```
If you are using foundry add the following to your `foundry.toml`: </br>
```shell
remappings=["cfmm-math-libraries/=node_modules/cfmm-math-libraries/"]
```
Alternatively add 
```json
"solidity.remappingsUnix": [
        "@cfmm-math-libraries/=node_modules/cfmm-math-libraries/",
   ]
``` 
to your `settings.json` in vscode.

Finally, simply import the contract and library into your contract:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "cfmm-math-libraries/src/CFMMQuoter.sol";
import "cfmm-math-libraries/src/libraries/CFMMMath.sol";
```

Inherit `CFMMQuoter` into your contract to access all internal logic:
```solidity
contract MyContract is CFMMQuoter {}
```
# Test Instructions
From the project route. </br>
Run Test Suite: 
```shell
forge test -f <RPC_ENDPOINT>  --fork-block-number 15233771
``` 
Run Gas Snapshot: 
```shell
forge snapshot -f <RPC_ENDPOINT> --fork-block-number 15233771
```

# Features
## CFMMQuoter
`CFMMQuoter.sol` offers a comprehensive tool suite for quoting amounts yielded from swaps, simulating price changes from input/output quantities, and inferring input/output quantities introduced/removed from a pool based on price changes. `CFMMQuoter` is a contract not a library. So, to cheaply utilize all of its core functions in your contract you can simply inherit `CFMMQuoter`.
### V3 Features
Precisely quotes the amount yielded from a swap on a v3 pool. This function can be used to determine a precise amountOutMin for a v3 swap on chain, and eliminates the need to use the v3 quoter saving a significant amount of gas. 
```solidity
function simulateAmountOutOnSqrtPriceX96(
    address token0,
    address tokenIn,
    address lpAddressAToWeth,
    uint256 amountIn,
    int24 tickSpacing,
    uint128 liquidity,
    uint24 fee
) internal returns (int256 amountOut
```
Simulates `tick` state of a v3 pool after swapping `amountIn` of `tokenIn`.
```solidity
function simulateNewTickOnInputAmountPrecise(
        address token0,
        address tokenIn,
        address lpAddressAToWeth,
        uint256 amountIn,
        int24 tickSpacing,
        uint128 liquidity,
        uint24 fee
    ) internal returns (int24 limitTick)
```
Calculates the exact amount introduced/removed from a v3 pool to move the price from `sqrtRatioAX96` to `sqrtRatioBX96`.
```solidity
function calculateDeltaAddedOnSqrtPriceChange(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amountDelta) {}
    
function calculateDeltaRemovedOnSqrtPriceChange(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amountDelta) {}
```
### V2 Features
Precisely Quotes the amount1 received on a v2 swap.
```solidity
function calculateAmountOutV2(
        uint256 amount0,
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (uint256 amount1) {}
```
Precisely calculates the spot price in a v2 pool after swapping `amount0`.
```solidity
function v2SimulateNewSpotFromInput(
        uint112 reserve0,
        uint112 reserve1,
        uint112 amount0
    ) internal pure returns (uint128) {}
```

## CFMMMath
CFMMMath provdes a tool suite for mathematical operations in 64.64 fixed point.
### V3 Functions
Converts sqrtRatioX96 (sqrt(spot price)) of form Q96.64 to 64.64 fixed point representation of the spot price normalized by token decimals, and directionally representative of the base/quote token.
```solidity
function fromSqrtX96ToX64(
        uint8 decimals0,
        uint8 decimals1,
        uint160 sqrtPriceX96,
        bool token0IsReserve0
    ) internal pure returns (uint128 priceX64) {}
```
Converts 64.64 fixed point representation of the spotPrice into sqrt(spotPrice) as Q96.64 unnormalized on token decimals.
```solidity
function from64XSpotToSqrtRatioX96(
        uint8 decimals0,
        uint8 decimals1,
        uint128 spot64X,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtRatioX96) {}
```
### V2 Functions
Calculates a v2 spot price from the pool reserves as a 64.64 fixed point number.
```solidity
function v2SpotPrice64x64(
        uint112 reserve0,
        uint112 reserve1,
        uint8 decimals0,
        uint8 decimals1
    ) internal pure returns (uint128) {}
```
Normalizes v2 reserves to a target decimal.
```solidity
function v2NormalizeReserves(
        uint112 _reserve0,
        uint112 _reserve1,
        uint8 decimals0,
        uint8 decimals1,
        uint8 _targetDecimals
    ) internal pure returns (uint112 reserve0, uint112 reserve1) {}
```
### Extra CFMM Helpers
```solidity
function proportionalPriceDifferenceUnsigned(uint128 x, uint128 y)
        internal
        pure
        returns (uint128)
    {}
function proportionalPriceDifferenceSigned(uint128 x, uint128 y)
        internal
        pure
        returns (int128)
    {}
```

### Standard Operation Functions
Converts unsigned integer to 64.64 fixed point. 
```solidity 
fromUInt256(uint256 x)
```
Converts 64.64 fixed point to unsigned integer. 
```solidity
toUInt(uint128 x)
``` 
Converts 128.128 fixed point to 64.64 fixed point. </br>
```solidity
from128x128(uint256 x)
```
Adds two 64.64 fixed point numbers. </br>
```solidity
add64x64(uint128 x, uint128 y)
```
Computes `a - b` where `a` is 64.64 fixed point, and `b` is an unsigned integer. </br>
```solidity
sub64x64U(int128 x, int128 y)
```
Computes `a - b` where `a` is 64.64 fixed point, and `b` is an nsigned integer. </br>
```solidity
sub64x64I(int128 x, int128 y)
```
Computes the product of two 64.64 fixed point numbers. </br>
```solidity
mul64x64(uint128 x, uint128 y)
```
Computes `a/b` where a & b are both 64.64 fixed point numbers. </br>
```solidity
div64x64(uint128 x, uint128 y)
```
Computes `a/b` where a & b are both unsigned integers and returns the result as 64.64 fixed point number. </br>
```solidity
divuu(uint256 x, uint256 y)
```
Computes the absolute value of a signed integer. </br>
```solidity
abs(int256 x)
```
Computes the binary exponent of a 64.64 fixed point number. </br>
```solidity
exp_2(uint128 x)
```
Computes the square root of an unsigned integer and returns the result as 64.64 fixed point number.</br>
```solidity
sqrtu(uint256 x)
```

# Additional Features Coming Soon
1.) Derive input quantity from 2 v2 prices. </br>
2.) Simulate Tick Change on output V3 </br>
3.) Simulate amountIn on exact output sqrtPriceX96 V3. </br>
4.) DODO Architecture Integration </br>
5.) Curve Architecture Integration </br>


Additionally feel free to open an issue on any features you would like integrated! 
