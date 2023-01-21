// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/libraries/Uniswap/FullMath.sol";
import "../lib/libraries/Uniswap/LowGasSafeMath.sol";
import "../lib/libraries/Uniswap/SafeCast.sol";
import "../lib/libraries/Uniswap/SqrtPriceMath.sol";
import "../lib/libraries/Uniswap/TickMath.sol";
import "../lib/libraries/Uniswap/TickBitmap.sol";
import "../lib/libraries/Uniswap/SwapMath.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/Uniswap/LowGasSafeMath.sol";
import "../lib/libraries/Uniswap/LiquidityMath.sol";
import "../lib/libraries/Uniswap/Tick.sol";
import "../lib/libraries/Uniswap/SafeCast.sol";
import "../lib/interfaces/token/IERC20.sol";
import "./libraries/CFMMMath.sol";

/// @title Constant Function Market Maker Solidity Fixed point math library.
/// @notice This contract contains functions that can  be used to simulate price changes and analytically simulate the amount received from Uniswap v2/v3 swaps
/// @author 0xOsiris
contract CFMMQuoter {
    ///@notice Initialize all libraries.
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    //==================================================Constants=====================================================//
    /// @notice maximum uint128 64.64 fixed point number
    uint128 private constant MAX_64x64 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    ///@notice Q96 shift constant i.e. 2**96 in hexidecimal.
    uint256 internal constant Q96 = 0x1000000000000000000000000;

    //-----------------------------------------------------------Structs-------------------------------------------------------------------//

    ///@notice Struct holding the current simulated swap state.
    ///@dev Simulation architecture modeled after: See https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol for full implementation.
    struct CurrentState {
        ///@notice Amount remaining to be swapped upon cross tick simulation.
        int256 amountSpecifiedRemaining;
        ///@notice The amount that has already been simulated over the whole swap.
        int256 amountCalculated;
        ///@notice Current price on the tick.
        uint160 sqrtPriceX96;
        ///@notice The current tick.
        int24 tick;
        ///@notice The liquidity on the current tick.
        uint128 liquidity;
    }

    ///@notice Struct holding the simulated swap state across swap steps.
    struct StepComputations {
        ///@notice The price at the beginning of the state.
        uint160 sqrtPriceStartX96;
        ///@notice The adjacent tick from the current tick in the swap simulation.
        int24 tickNext;
        ///@notice Whether tickNext is initialized or not.
        bool initialized;
        ///@notice The sqrt(price) for the next tick (1/0).
        uint160 sqrtPriceNextX96;
        ///@notice How much is being swapped in in this step.
        uint256 amountIn;
        ///@notice How much is being swapped out.
        uint256 amountOut;
        ///@notice The fee being paid on the swap.
        uint256 feeAmount;
    }

    //==================================================Uniswap V3 Simulation Logic =====================================================//

    ///@notice Function to simulate the change in sqrt price on a uniswap v3 swap.
    ///@param token0 Token 0 in the v3 pool.
    ///@param tokenIn Token 0 in the v3 pool.
    ///@param pool The address of the pool.
    ///@param amountIn The amount in to simulate the price change on.
    ///@param tickSpacing The tick spacing on the pool.
    ///@param liquidity The liquidity in the pool.
    ///@param fee The swap fee in the pool.
    function simulateAmountOutOnSqrtPriceX96(
        address token0,
        address tokenIn,
        address pool,
        uint256 amountIn,
        int24 tickSpacing,
        uint128 liquidity,
        uint24 fee
    ) internal view returns (int256 amountOut, uint160 nextSqrtPriceX96) {
        ///@notice If token0 in the pool is tokenIn then set zeroForOne to true.
        bool zeroForOne = token0 == tokenIn ? true : false;

        CurrentState memory currentState;

        ///@notice Scope to prevent stack too deep.
        {
            ///@notice Grab the current price and the current tick in the pool.
            (
                uint160 sqrtPriceX96,
                int24 initialTick,
                ,
                ,
                ,
                ,

            ) = IUniswapV3Pool(pool).slot0();

            ///@notice Initialize the initial simulation state
            currentState = CurrentState({
                sqrtPriceX96: sqrtPriceX96,
                amountCalculated: 0,
                amountSpecifiedRemaining: int256(amountIn),
                tick: initialTick,
                liquidity: liquidity
            });
        }

        uint160 sqrtPriceLimitX96 = zeroForOne
            ? TickMath.MIN_SQRT_RATIO + 1
            : TickMath.MAX_SQRT_RATIO - 1;

        ///@notice While the current state still has an amount to swap continue.
        while (currentState.amountSpecifiedRemaining > 0) {
            ///@notice Initialize step structure.
            StepComputations memory step;
            ///@notice Set sqrtPriceStartX96.
            step.sqrtPriceStartX96 = currentState.sqrtPriceX96;
            ///@notice Set the tickNext, and if the tick is initialized.
            (step.tickNext, step.initialized) = TickBitmap
                .nextInitializedTickWithinOneWord(
                    currentState.tick,
                    tickSpacing,
                    zeroForOne,
                    pool
                );
            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }
            ///@notice Set the next sqrtPrice of the step.
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);
            ///@notice Perform the swap step on the current tick.
            (
                currentState.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                currentState.sqrtPriceX96,
                (
                    zeroForOne
                        ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                        : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                )
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                currentState.liquidity,
                currentState.amountSpecifiedRemaining,
                fee
            );
            ///@notice Decrement the remaining amount to be swapped by the amount available within the tick range.
            currentState.amountSpecifiedRemaining -= (step.amountIn +
                step.feeAmount).toInt256();
            ///@notice Increment amountCalculated by the amount recieved in the tick range.
            currentState.amountCalculated -= step.amountOut.toInt256();
            ///@notice If the swap step crossed into the next tick, and that tick is initialized.
            if (currentState.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    ///@notice Get the net liquidity after crossing the tick.
                    (, int128 liquidityNet, , , , , , ) = IUniswapV3Pool(
                        pool
                    ).ticks(step.tickNext);

                    ///@notice If swapping token0 for token1 then negate the liquidtyNet.

                    if (zeroForOne) liquidityNet = -liquidityNet;

                    currentState.liquidity = LiquidityMath.addDelta(
                        currentState.liquidity,
                        liquidityNet
                    );
                }
                ///@notice Update the currentStates tick.
                unchecked {
                    currentState.tick = zeroForOne
                        ? step.tickNext - 1
                        : step.tickNext;
                }
                ///@notice If sqrtPriceX96 in the currentState is not equal to the projected next tick, then recompute the currentStates tick.
            } else if (currentState.sqrtPriceX96 != step.sqrtPriceStartX96) {
                currentState.tick = TickMath.getTickAtSqrtRatio(
                    currentState.sqrtPriceX96
                );
            }
        }
        ///@notice Return the simulated amount out as a negative value representing the amount recieved in the swap.
        return (currentState.amountCalculated, currentState.sqrtPriceX96);
    }

    ///@notice Helper function to calculate the sqrtPriceLimitX96 for a swap.
    ///@param zeroForOne Bool indicating whether the amountIn is on token0 or token1 in the pool.
    ///@return sqrtPriceLimitX96 The upper bound on the price change in the pool.
    ///@dev sqrtPriceLimitX96 can be used as a valid swap parameter on the pool when interacting with the pool directly and circumventing the SwapRouter.
    function calculateSqrtPriceLimitX96(
        bool zeroForOne
    ) internal pure returns (uint160 sqrtPriceLimitX96) {
        return zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
    }

    ///@notice Helper function to determine the upper limit tick from a swap.
    ///@dev This tick is guaranteed not to be crossed upon swapping in a pool. It is representitive of the nearest initialized tick to the sqrtPriceLimitX96.
    ///@param token0 Token 0 in the v3 pool.
    ///@param tokenIn TokenIn on the swap in the v3 pool.
    ///@param lpAddressAToWeth The tokenA to weth liquidity pool address.
    ///@param amountIn The amount in to simulate the price change on.
    ///@param tickSpacing The tick spacing on the pool.
    ///@param liquidity The liquidity in the pool.
    ///@param fee The swap fee in the pool.
    ///@return limitTick The new current tick in the pool after swapping the specified amount of tokenIn.
    function simulateNewTickOnInputAmountPrecise(
        address token0,
        address tokenIn,
        address lpAddressAToWeth,
        uint256 amountIn,
        int24 tickSpacing,
        uint128 liquidity,
        uint24 fee
    ) internal returns (int24 limitTick) {
        ///@notice If token0 in the pool is tokenIn then set zeroForOne to true.
        bool zeroForOne = token0 == tokenIn ? true : false;

        ///@notice Grab the current price and the current tick in the pool.
        (uint160 sqrtPriceX96, int24 initialTick, , , , , ) = IUniswapV3Pool(
            lpAddressAToWeth
        ).slot0();

        ///@notice Initialize the initial simulation state
        CurrentState memory currentState = CurrentState({
            sqrtPriceX96: sqrtPriceX96,
            amountCalculated: 0,
            amountSpecifiedRemaining: int256(amountIn),
            tick: initialTick,
            liquidity: liquidity
        });

        uint160 sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
            sqrtPriceX96,
            liquidity,
            amountIn,
            zeroForOne
        );

        ///@notice While the current state still has an amount to swap continue.
        while (currentState.amountSpecifiedRemaining > 0) {
            ///@notice Initialize step structure.
            StepComputations memory step;
            ///@notice Set sqrtPriceStartX96.
            step.sqrtPriceStartX96 = currentState.sqrtPriceX96;
            ///@notice Set the tickNext, and if the tick is initialized.
            ///@notice Set the tickNext, and if the tick is initialized.
            (step.tickNext, step.initialized) = TickBitmap
                .nextInitializedTickWithinOneWord(
                    currentState.tick,
                    tickSpacing,
                    zeroForOne,
                    lpAddressAToWeth
                );
            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }
            ///@notice Set the next sqrtPrice of the step.
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);
            ///@notice Perform the swap step on the current tick.
            (
                currentState.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                currentState.sqrtPriceX96,
                (
                    zeroForOne
                        ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                        : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                )
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                currentState.liquidity,
                currentState.amountSpecifiedRemaining,
                fee
            );
            ///@notice Decrement the remaining amount to be swapped by the amount available within the tick range.
            currentState.amountSpecifiedRemaining -= (step.amountIn +
                step.feeAmount).toInt256();
            ///@notice Increment amountCalculated by the amount recieved in the tick range.
            currentState.amountCalculated -= step.amountOut.toInt256();
            ///@notice If the swap step crossed into the next tick, and that tick is initialized.
            if (currentState.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    ///@notice Get the net liquidity after crossing the tick.
                    (, int128 liquidityNet, , , , , , ) = IUniswapV3Pool(
                        lpAddressAToWeth
                    ).ticks(step.tickNext);
                    ///@notice If swapping token0 for token1 then negate the liquidtyNet.

                    if (zeroForOne) liquidityNet = -liquidityNet;

                    currentState.liquidity = LiquidityMath.addDelta(
                        currentState.liquidity,
                        liquidityNet
                    );
                }
                ///@notice Update the currentStates tick.
                unchecked {
                    currentState.tick = zeroForOne
                        ? step.tickNext - 1
                        : step.tickNext;
                }
                ///@notice If sqrtPriceX96 in the currentState is not equal to the projected next tick, then recompute the currentStates tick.
            } else if (currentState.sqrtPriceX96 != step.sqrtPriceStartX96) {
                currentState.tick = TickMath.getTickAtSqrtRatio(
                    currentState.sqrtPriceX96
                );
            }
        }

        ///@notice Return the simulated new tick after swapping the specified amount on the v3 pool.
        return currentState.tick;
    }

    ///@notice Simple helper to get the tick at some sqrtRatio in a v3 pool.
    ///@dev Personally reccomend not using this function and simply calling the TickMath library within your contract to save gas.
    ///@param sqrtPriceX96 The price to determine the initialized tick in the range of.
    ///@return tick The initialized tick in the pool at that price.
    function getTickAtSqrtPriceX96(uint160 sqrtPriceX96)
        internal
        pure
        returns (int24 tick)
    {
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    ///@notice Simple helper to get the tick at some sqrtRatio in a v3 pool.
    ///@dev Personally reccomend not using this function and simply calling the TickMath library within your contract to save gas.
    ///@param tick The tick to determine the sqrt price of.
    ///@return sqrtPriceX96 The sqrtPrice in the pool at the tick.
    function getSqrtPriceX96AtTick(int24 tick)
        internal
        pure
        returns (uint160 sqrtPriceX96)
    {
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
    }

    ///@notice Helper function to determine the amount of a specified token introduced into a v3 pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96.
    ///@dev If the prices are in 64.64 fixed point form simply call from64XSpotToSqrtRatioX96 in the CFMMMath library to convert the prices into a the correct form.
    ///@param sqrtRatioAX96 The initial price of the pool.
    ///@param sqrtRatioBX96 The Quote price to determine the delta introduced to the pool on.
    ///@param liquidity The current liqudity in the pool.
    ///@return amountDelta The amount of tokenX introduced to the pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96.
    ///@dev Note This is simply returning the amount of tokenX to be introduced to the pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96. To calculate the amount removed use calculateDeltaRemovedOnSqrtPriceChange.
    function calculateDeltaAddedOnSqrtPriceChange(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amountDelta) {
        ///@notice Determine if the price is decresing or increasing.
        bool priceIncrease = sqrtRatioAX96 > sqrtRatioBX96 ? false : true;

        ///@notice Conditionally evaluate the amountDelta in the pool, depending on whether the price increased or decreased.
        if (!priceIncrease) {
            amountDelta = SqrtPriceMath.getAmount0Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                false
            );
        } else {
            amountDelta = SqrtPriceMath.getAmount1Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                false
            );
        }
    }

    ///@notice Helper function to determine the amount of a specified token removed from a v3 pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96.
    ///@dev If the prices are in 64.64 fixed point form simply call from64XSpotToSqrtRatioX96 in the CFMMMath library to convert the prices into a the correct form.
    ///@param sqrtRatioAX96 The initial price of the pool.
    ///@param sqrtRatioBX96 The Quote price to determine the delta introduced to the pool on.
    ///@param liquidity The current liqudity in the pool.
    ///@return amountDelta The amount of tokenX removed from the pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96.
    ///@dev Note This is simply returning the amount of tokenX to be removed from the pool to move the price from sqrtRatioAX96 -> sqrtRatioBX96. To calculate the amount introduced use calculateDeltaAddedOnSqrtPriceChange.
    function calculateDeltaRemovedOnSqrtPriceChange(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amountDelta) {
        ///@notice Determine if the price is decresing or increasing.
        bool priceIncrease = sqrtRatioAX96 > sqrtRatioBX96 ? false : true;

        ///@notice Conditionally evaluate the amountDelta in the pool, depending on whether the price increased or decreased.
        if (!priceIncrease) {
            amountDelta = SqrtPriceMath.getAmount1Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                false
            );
        } else {
            amountDelta = SqrtPriceMath.getAmount0Delta(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity,
                false
            );
        }
    }

    //==================================================Uniswap V2 Simulation Logic =====================================================//

    ///@notice Function to get the amountOut from a UniV2 lp.
    ///@param amount0 - AmountIn for the swap.
    ///@param reserve0 - tokenIn reserve for the swap.
    ///@param reserve1 - tokenOut reserve for the swap.
    ///@return amount1 - AmountOut from the given parameters.
    function calculateAmountOutV2(
        uint256 amount0,
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (uint256 amount1) {
        require(
            amount0 != 0 && reserve0 != 0 && reserve1 != 0,
            "Invalid input"
        );
        uint256 amount0WithFee = amount0 * 997;
        uint256 numerator = amount0WithFee * reserve1;
        uint256 denominator = reserve0 * 1000 + (amount0WithFee);
        amount1 = numerator / denominator;
    }

    ///@notice helper to calculate the simulated spot price of token0 in a v2 pool represented as 64.64 fixed point after amount0 is introduced to the pool.
    ///@dev Assumed normalized reserve values for normalized spotPrice output.
    ///@param reserve0 The token0 reserves in the pool.
    ///@param reserve1 The token1 reserves in the pool.
    ///@return unsigned The spot price of token0 in 64.64 fixed point.
    function v2SimulateNewSpotFromInput(
        uint112 reserve0,
        uint112 reserve1,
        uint112 amount0
    ) internal pure returns (uint128) {
        unchecked {
            uint256 amount0WithFee = amount0 * 997;
            uint256 newReserve0 = uint256(reserve0) + amount0WithFee;
            uint256 k = uint256(reserve0) * reserve1;
            uint256 newReserve1 = (k / newReserve0) / 1000;
            uint128 spotPrice = CFMMMath.divuu(newReserve1, newReserve0);
            require(spotPrice <= MAX_64x64);
            return spotPrice;
        }
    }
}
