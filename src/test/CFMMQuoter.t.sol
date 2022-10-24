// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "../CFMMQuoter.sol";
import "../../lib/interfaces/uniswap-v3/IQuoter.sol";
import "./utils/SwapV3.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract CFMMQuoterTest is DSTest {
    ///@notice Initialize test contract instances.
    CFMMQuoterWrapper cfmmQuoter;
    IQuoter iQuoter;
    Swap testSwapper;
    SwapV3 testSwapperV3;

    ///@notice Initialize cheatcodes.
    CheatCodes cheatCodes;

    ///@notice Test Token Addresses.
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    ///@notice Test V3 Pool addresses and pool fees.
    address daiWethPoolV3 = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    uint24 constant DAI_WETH_FEE = 3000;

    address usdcDaiPoolV3 = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;
    uint24 constant USDC_DAI_FEE = 500;

    ///@notice Test V2 Pool addresses and pool fees.
    address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;

    ///@notice Set the v2 router address for test swaps.
    address v2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ///@notice Set the v3 quoter address.
    address v3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    ///@notice Setup to initialize all relevant contract instances used throughout the test suite.
    function setUp() public {
        ///@notice Initialize testSwapper contracts.
        testSwapper = new Swap(v2Router, WETH);
        testSwapperV3 = new SwapV3();
        ///@notice Initalize cheatCodes
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        ///@notice Iniialize ConveyorTickMath contract wrapper
        cfmmQuoter = new CFMMQuoterWrapper();
        ///@notice Initialize the v3 quoter
        iQuoter = IQuoter(v3Quoter);
    }

    //=======================================================================Uniswap V3 Tests============================================================================//
    ///@notice Validates quote amountOut against the v3 quoter in the case when quoting token1 in the pool.
    function testSimulateAmountOutOnSqrtPriceX96_ZeroForOne_True(
        uint112 amountIn
    ) public {
        bool run = true;
        //range 10-10000 dai
        if (
            amountIn < 1000000000000000000 ||
            amountIn > 1000000000000000000000
        ) {
            run = false;
        }

        if (run) {
            //Grab all relevant storage data from the v3 pool
            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3)
                .slot0();
            int24 tickSpacing = IUniswapV3Pool(daiWethPoolV3).tickSpacing();
            address token0 = IUniswapV3Pool(daiWethPoolV3).token0();
            uint128 liquidity = IUniswapV3Pool(daiWethPoolV3).liquidity();

            //Calculate the change in price on the input quantity
            uint160 sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                sqrtPriceX96,
                liquidity,
                amountIn,
                true
            );

            //Get the quoted amount out from _simulateAmountOutOnSqrtPriceX96.
            uint256 amountOutToValidate = uint256(
                -cfmmQuoter._simulateAmountOutOnSqrtPriceX96(
                    token0,
                    DAI,
                    daiWethPoolV3,
                    amountIn,
                    tickSpacing,
                    liquidity,
                    DAI_WETH_FEE
                )
            );

            //Get the expected amountOut in Dai from the v3 quoter.
            uint256 amountOutExpected = iQuoter.quoteExactInputSingle(
                DAI,
                WETH,
                DAI_WETH_FEE,
                amountIn,
                sqrtPriceLimitX96
            );

            console.log(amountOutToValidate);

            {
                //Deal the swapHelper eth
                cheatCodes.deal(address(testSwapper), type(uint128).max);

                //Swap eth for DAI
                testSwapper.swapEthForTokenWithUniV2(
                    100000000000000000000000,
                    DAI
                );
                uint256 daiBal = IERC20(DAI).balanceOf(address(this));

                IERC20(DAI).transfer(address(testSwapperV3), daiBal);

                //Attempt a swap on our derived quote
                uint256 amountReceived = testSwapperV3.swapV3(
                    daiWethPoolV3,
                    true,
                    DAI,
                    amountIn,
                    amountOutToValidate,
                    sqrtPriceLimitX96,
                    address(this)
                );

                //Make sure we got at least our quote from the swap
                assertGe(amountReceived, amountOutToValidate);

                //Ensure they are equal within 10000 wei
                assertEq(amountOutToValidate / 10000, amountOutExpected / 10000);
            }
        }
    }

    ///@notice Validates quote amountOut against the v3 quoter in the case when quoting token0 in the pool.
    function testSimulateAmountOutOnSqrtPriceX96_ZeroForOne_False(
        uint112 amountIn
    ) public {
        bool run = true;
        {
            if (
                amountIn < 1000000000000000000 ||
                amountIn > 10000000000000000000
            ) {
                run = false;
            }
        }

        if (run) {
            //Grab all relevant storage data from the v3 pool
            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3)
                .slot0();
            int24 tickSpacing = IUniswapV3Pool(daiWethPoolV3).tickSpacing();
            address token0 = IUniswapV3Pool(daiWethPoolV3).token0();
            uint128 liquidity = IUniswapV3Pool(daiWethPoolV3).liquidity();

            //Calculate the change in price on the input quantity
            uint160 sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                sqrtPriceX96,
                liquidity,
                amountIn,
                false
            );

            //Get the quoted amount out from _simulateAmountOutOnSqrtPriceX96.
            uint256 amountOutToValidate = uint256(
                -cfmmQuoter._simulateAmountOutOnSqrtPriceX96(
                    token0,
                    WETH,
                    daiWethPoolV3,
                    amountIn,
                    tickSpacing,
                    liquidity,
                    DAI_WETH_FEE
                )
            );

            //Get the expected amountOut in Dai from the v3 quoter.
            uint256 amountOutExpected = iQuoter.quoteExactInputSingle(
                WETH,
                DAI,
                DAI_WETH_FEE,
                amountIn,
                sqrtPriceLimitX96
            );

            console.log(amountOutToValidate);

            {
                //Deal some ether to the test contract
                cheatCodes.deal(address(this), amountIn + type(uint16).max);

                //Wrap the Ether
                address(WETH).call{value: amountIn + type(uint16).max}(
                    abi.encodeWithSignature("deposit()")
                );

                //Transfer the input amount to the SwapRotuer contract to be sent to the pool in the swap callback.
                IERC20(WETH).transfer(
                    address(testSwapperV3),
                    amountIn + type(uint16).max
                );

                //Attempt a swap on our derived quote
                uint256 amountReceived = testSwapperV3.swapV3(
                    daiWethPoolV3,
                    false,
                    WETH,
                    amountIn,
                    amountOutToValidate,
                    sqrtPriceLimitX96,
                    address(this)
                );

                //Make sure we got at least our quote from the swap
                assertGe(amountReceived, amountOutToValidate);

                //Ensure they are equal within 10000 wei
                assertEq(amountOutToValidate / 10000, amountOutExpected / 10000);
            }
        }
    }

    ///@notice Validates the computed sqrtPriceLimitX96 by mocking a v3 swap.
    function testCalculateSqrtPriceLimitX96_ZeroForOne_True(uint112 amountIn)
        public
    {
        bool run = true;
        //range 10-10000 dai
        if (
            amountIn < 10000000000000000000 || amountIn > 100000000000000000000
        ) {
            run = false;
        }

        if (run) {
            //Grab all relevant storage data from the v3 pool
            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3)
                .slot0();
            uint128 liquidity = IUniswapV3Pool(daiWethPoolV3).liquidity();

            //Calculate the change in price on the input quantity
            uint160 sqrtPriceLimitX96 = cfmmQuoter._calculateSqrtPriceLimitX96(
                sqrtPriceX96,
                liquidity,
                amountIn,
                true
            );

            {
                //Deal the swapHelper eth
                cheatCodes.deal(address(testSwapper), type(uint128).max);

                //Swap eth for DAI
                testSwapper.swapEthForTokenWithUniV2(
                    100000000000000000000000,
                    DAI
                );
                uint256 daiBal = IERC20(DAI).balanceOf(address(this));

                IERC20(DAI).transfer(address(testSwapperV3), daiBal);

                //Attempt a swap on our derived sqrtPriceLimit
                uint256 amountReceived = testSwapperV3.swapV3(
                    daiWethPoolV3,
                    true,
                    DAI,
                    amountIn,
                    1,
                    sqrtPriceLimitX96,
                    address(this)
                );
            }
        }
    }

    ///@notice Validates the computed sqrtPriceLimitX96 by mocking a v3 swap.
    function testCalculateSqrtPriceLimitX96_ZeroForOne_False(uint112 amountIn)
        public
    {
        bool run = true;
        //range 10-10000 dai
        if (
            amountIn < 10000000000000000000 || amountIn > 100000000000000000000
        ) {
            run = false;
        }

        if (run) {
            //Grab all relevant storage data from the v3 pool
            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3)
                .slot0();
            uint128 liquidity = IUniswapV3Pool(daiWethPoolV3).liquidity();

            //Calculate the change in price on the input quantity
            uint160 sqrtPriceLimitX96 = cfmmQuoter._calculateSqrtPriceLimitX96(
                sqrtPriceX96,
                liquidity,
                amountIn,
                false
            );

            {
                //Deal some ether to the test contract
                cheatCodes.deal(address(this), amountIn + type(uint16).max);

                //Wrap the Ether
                address(WETH).call{value: amountIn + type(uint16).max}(
                    abi.encodeWithSignature("deposit()")
                );

                //Transfer the input amount to the SwapRotuer contract to be sent to the pool in the swap callback.
                IERC20(WETH).transfer(
                    address(testSwapperV3),
                    amountIn + type(uint16).max
                );

                //Attempt a swap on our derived sqrtPriceLimit
                uint256 amountReceived = testSwapperV3.swapV3(
                    daiWethPoolV3,
                    false,
                    WETH,
                    amountIn,
                    1,
                    sqrtPriceLimitX96,
                    address(this)
                );
            }
        }
    }

    ///@notice Validates the computed tick after simulating the amountIn on the v3 pool.
    function testSimulateNewTickOnInputAmount(uint112 amountIn) public {
        bool run = true;
        //range 10-10000 dai
        if (
            amountIn < 10000000000000000000 || amountIn > 100000000000000000000
        ) {
            run = false;
        }
        if (run) {
            //Grab all relevant storage data from the v3 pool
            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3)
                .slot0();
            uint128 liquidity = IUniswapV3Pool(daiWethPoolV3).liquidity();
            int24 tickSpacing = IUniswapV3Pool(daiWethPoolV3).tickSpacing();
            address token0 = IUniswapV3Pool(daiWethPoolV3).token0();

            //Calculate the change in price on the input quantity
            uint160 sqrtPriceLimitX96 = cfmmQuoter._calculateSqrtPriceLimitX96(
                sqrtPriceX96,
                liquidity,
                amountIn,
                false
            );

            int24 simulatedTick = cfmmQuoter
                ._simulateNewTickOnInputAmountPrecise(
                    DAI,
                    WETH,
                    daiWethPoolV3,
                    amountIn,
                    tickSpacing,
                    liquidity,
                    DAI_WETH_FEE
                );

            {
                //Deal some ether to the test contract
                cheatCodes.deal(address(this), amountIn + type(uint16).max);

                //Wrap the Ether
                address(WETH).call{value: amountIn + type(uint16).max}(
                    abi.encodeWithSignature("deposit()")
                );

                //Transfer the input amount to the SwapRotuer contract to be sent to the pool in the swap callback.
                IERC20(WETH).transfer(
                    address(testSwapperV3),
                    amountIn + type(uint16).max
                );

                //Attempt a swap on our derived sqrtPriceLimit
                uint256 amountReceived = testSwapperV3.swapV3(
                    daiWethPoolV3,
                    false,
                    WETH,
                    amountIn,
                    1,
                    sqrtPriceLimitX96,
                    address(this)
                );

                (, int24 tick, , , , , ) = IUniswapV3Pool(daiWethPoolV3)
                    .slot0();

                assertEq(simulatedTick, tick);
            }
        }
    }

    ///@notice Validates the computed delta added on the price change.
    function testCalculateDeltaAddedOnSqrtPriceChange(uint112 deltaAdded)
        public
    {
        bool run = true;
        //range 10-10000 dai
        if (
            deltaAdded < 10000000000000000000 ||
            deltaAdded > 100000000000000000000
        ) {
            run = false;
        }

        if (run) {
            //Grab all relevant storage data from the v3 pool
            (uint160 sqrtRatioAX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3)
                .slot0();
            uint128 liquidity = IUniswapV3Pool(daiWethPoolV3).liquidity();
            

            //Calculate the change in price on the input quantity
            uint160 sqrtPriceLimitX96 = cfmmQuoter._calculateSqrtPriceLimitX96(
                sqrtRatioAX96,
                liquidity,
                deltaAdded,
                true
            );
            //Deal the swapHelper eth
            cheatCodes.deal(address(testSwapper), type(uint128).max);

            //Swap eth for DAI
            testSwapper.swapEthForTokenWithUniV2(100000000000000000000000, DAI);
            uint256 daiBal = IERC20(DAI).balanceOf(address(this));

            IERC20(DAI).transfer(address(testSwapperV3), daiBal);

            //Attempt a swap on our derived sqrtPriceLimit
            uint256 amountReceived = testSwapperV3.swapV3(
                daiWethPoolV3,
                true,
                DAI,
                deltaAdded,
                1,
                sqrtPriceLimitX96,
                address(this)
            );


            uint256 deltaAddedToValidate = cfmmQuoter._calculateDeltaAddedOnSqrtPriceChange(sqrtRatioAX96, sqrtPriceLimitX96, liquidity);
            uint256 deltaAddedUpper = deltaAdded + 2;
            uint256 deltaAddedLower = deltaAdded-2;
            assertGt(deltaAddedToValidate, deltaAddedLower);
            assertLt(deltaAddedToValidate, deltaAddedUpper);
        }
    }

    ///@notice Validates the computed delta removed on the price change.
    function testCalculateDeltaRemovedOnSqrtPriceChange(uint112 amountIn) public {
        bool run = true;
        //range 10-10000 dai
        if (
            amountIn < 10000000000000000000 ||
            amountIn > 100000000000000000000
        ) {
            run = false;
        }

        if (run) {
            //Grab all relevant storage data from the v3 pool
            (uint160 sqrtRatioAX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3)
                .slot0();
            uint128 liquidity = IUniswapV3Pool(daiWethPoolV3).liquidity();
            

            //Calculate the change in price on the input quantity
            uint160 sqrtPriceLimitX96 = cfmmQuoter._calculateSqrtPriceLimitX96(
                sqrtRatioAX96,
                liquidity,
                amountIn,
                true
            );
            //Deal the swapHelper eth
            cheatCodes.deal(address(testSwapper), type(uint128).max);

            //Swap eth for DAI
            testSwapper.swapEthForTokenWithUniV2(100000000000000000000000, DAI);
            uint256 daiBal = IERC20(DAI).balanceOf(address(this));

            IERC20(DAI).transfer(address(testSwapperV3), daiBal);
            //Get the expected amountOut in Dai from the v3 quoter.
            uint256 amountOutExpected = iQuoter.quoteExactInputSingle(
                DAI,
                WETH,
                DAI_WETH_FEE,
                amountIn,
                sqrtPriceLimitX96
            );
            //Attempt a swap on our derived sqrtPriceLimit
            uint256 amountReceived = testSwapperV3.swapV3(
                daiWethPoolV3,
                true,
                DAI,
                amountIn,
                amountOutExpected,
                sqrtPriceLimitX96,
                address(this)
            );

            (uint160 sqrtRatioBX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3).slot0();
            uint256 deltaRemovedToValidate = cfmmQuoter._calculateDeltaRemovedOnSqrtPriceChange(sqrtRatioAX96, sqrtRatioBX96, liquidity);

            uint256 deltaRemovedUpper = amountReceived + 2;
            uint256 deltaRemovedLower = amountReceived-2;
            assertGt(deltaRemovedToValidate, deltaRemovedLower);
            assertLt(deltaRemovedToValidate, deltaRemovedUpper);
        }
    }

    
}

contract CFMMQuoterWrapper is CFMMQuoter {
    function _simulateAmountOutOnSqrtPriceX96(
        address token0,
        address tokenIn,
        address lpAddressAToWeth,
        uint256 amountIn,
        int24 tickSpacing,
        uint128 liquidity,
        uint24 fee
    ) public returns (int256 amountOut) {
        return
            simulateAmountOutOnSqrtPriceX96(
                token0,
                tokenIn,
                lpAddressAToWeth,
                amountIn,
                tickSpacing,
                liquidity,
                fee
            );
    }

    function _calculateSqrtPriceLimitX96(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint128 amountIn,
        bool zeroForOne
    ) public pure returns (uint160 sqrtPriceLimitX96) {
        return
            calculateSqrtPriceLimitX96(
                sqrtPriceX96,
                liquidity,
                amountIn,
                zeroForOne
            );
    }

    function _calculateSqrtPriceLimitX96Simple(
        address poolAddress,
        uint128 amountIn,
        bool zeroForOne
    ) public view returns (uint160 sqrtPriceLimitX96) {
        return
            calculateSqrtPriceLimitX96Simple(poolAddress, amountIn, zeroForOne);
    }

    function _simulateNewTickOnInputAmountPrecise(
        address token0,
        address tokenIn,
        address lpAddressAToWeth,
        uint256 amountIn,
        int24 tickSpacing,
        uint128 liquidity,
        uint24 fee
    ) public returns (int24 limitTick) {
        return
            simulateNewTickOnInputAmountPrecise(
                token0,
                tokenIn,
                lpAddressAToWeth,
                amountIn,
                tickSpacing,
                liquidity,
                fee
            );
    }

    function _calculateDeltaAddedOnSqrtPriceChange(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) public pure returns (uint256 amountDelta) {
        return
            calculateDeltaAddedOnSqrtPriceChange(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity
            );
    }

    function _calculateDeltaRemovedOnSqrtPriceChange(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) public pure returns (uint256 amountDelta) {
        return
            calculateDeltaRemovedOnSqrtPriceChange(
                sqrtRatioAX96,
                sqrtRatioBX96,
                liquidity
            );
    }

    function _v2SimulateNewSpotFromInput(
        uint112 reserve0,
        uint112 reserve1,
        uint112 amount0
    ) public pure returns (uint128) {
        return v2SimulateNewSpotFromInput(reserve0, reserve1, amount0);
    }

    function _calculateAmountOutV2(
        uint256 amount0,
        uint256 reserve0,
        uint256 reserve1
    ) public pure returns (uint256 amount1) {
        return calculateAmountOutV2(amount0, reserve0, reserve1);
    }
}
