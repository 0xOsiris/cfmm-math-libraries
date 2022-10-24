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
import "../libraries/CFMMMath.sol";
import "../../lib/interfaces/uniswap-v3/IQuoter.sol";
import "./utils/SwapV3.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract CFMMMathTest is DSTest {
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
    address usdcWethV2 = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

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

        ///@notice Initialize the v3 quoter
        iQuoter = IQuoter(v3Quoter);
    }

    //=================================================V2===============================================//

    //Block number 15233771
    function testV2SpotPrice64x64() public {
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(daiWethV2).getReserves();
        uint8 decimals0 = IERC20(DAI).decimals();
        uint8 decimals1 = IERC20(WETH).decimals();
        uint128 spotPrice64x64 = CFMMMath.v2SpotPrice64x64(
            r0,
            r1,
            decimals0,
            decimals1
        );
        assertEq(spotPrice64x64, 10578178921292524);
    }

    function testV2NormalizeReserves() public {
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(usdcWethV2).getReserves();
        uint8 decimalsUsdc = 6;
        uint8 decimalsWeth = 18;
        uint112 expectedR0 = r0 * 10**12;
        uint112 expectedR1 = r1;

        (uint112 r0ToValidate, uint112 r1ToValidate) = CFMMMath
            .v2NormalizeReserves(r0, r1, decimalsUsdc, decimalsWeth, 18);

        assertEq(r0ToValidate, expectedR0);
        assertEq(r1ToValidate, expectedR1);
    }

    //=================================================V3===============================================//
    //Block number 15233771
    function testFromSqrtX96ToX64() public {
        //Grab all relevant storage data from the v3 pool
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3)
            .slot0();
        uint128 spot64X = CFMMMath.fromSqrtX96ToX64(18, 18, sqrtPriceX96, true);

        assertEq(spot64X, 10582860314283045);
    }

    function testFrom64XSpotToSqrtRatioX96() public {
        //Grab all relevant storage data from the v3 pool
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(daiWethPoolV3)
            .slot0();
        uint128 spot64X = CFMMMath.fromSqrtX96ToX64(18, 18, sqrtPriceX96, true);
        uint160 sqrtPriceX96ToValidate = CFMMMath.from64XSpotToSqrtRatioX96(
            18,
            18,
            spot64X,
            true
        );
        //Expect < 0.000000000000001 margin of error on conversion or 0.0000000000001%
        uint160 errorBuffer = 79228162514264;
        uint160 errorRealized;
        if (sqrtPriceX96ToValidate >= sqrtPriceX96) {
            errorRealized = uint160(
                FullMath.mulDiv(
                    sqrtPriceX96ToValidate,
                    CFMMMath.Q96,
                    sqrtPriceX96
                )
            );
        } else {
            errorRealized = uint160(
                FullMath.mulDiv(
                    sqrtPriceX96,
                    CFMMMath.Q96,
                    sqrtPriceX96ToValidate
                )
            );
        }

        uint160 proportionalDif = errorRealized - CFMMMath.Q96;

        assertGt(errorBuffer, proportionalDif);
    }
}
