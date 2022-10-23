// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../../lib/libraries/ABDK/QuadruplePrecision.sol";
import "../../lib/libraries/Uniswap/FullMath.sol";

/// @title Constant Function Market Maker Solidity Fixed point math library. This library can be used to easily convert Cfmm prices into a standardized 64x64 format.
/// @notice Contains functions for converting prices between 64.64 & Q96.64 fixed point, as well as v2/v3 price simulation and quoting logic.
/// @author 0xOsiris
library CFMMMath {
    /// @notice maximum uint128 64.64 fixed point number
    uint128 private constant MAX_64x64 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    ///@notice Decimal bits of a Q96.64 fixed point number, i.e 2**96
    uint256 internal constant Q96 = 0x1000000000000000000000000;

    ///@notice minimum unsigned 64.64 fixed point number
    uint256 internal constant MIN_64x64 = 0x0;

    /// @notice minimum int128 64.64 fixed point number
    int128 private constant MIN_64x64_Signed =
        -0x80000000000000000000000000000000;

    ///@notice Constant 1 in 64.64 fixed point
    uint128 internal constant ONE_64x64 = 0x10000000000000000;

    //====================================================Standard Operations=============================================================//

    /// @notice helper function to transform uint256 number to uint128 64.64 fixed point representation
    /// @param x unsigned 256 bit unsigned integer number
    /// @return unsigned 64.64 unsigned fixed point number
    function fromUInt256(uint256 x) internal pure returns (uint128) {
        unchecked {
            require(x <= 0xFFFFFFFFFFFFFFFF);
            return uint128(x << 64);
        }
    }

    /// @notice helper function to transform 64.64 fixed point uint128 to uint64 integer number
    /// @param x unsigned 64.64 fixed point number
    /// @return unsigned uint64 integer representation
    function toUInt(uint128 x) internal pure returns (uint64) {
        unchecked {
            return uint64(x >> 64);
        }
    }

    /// @notice helper to convert 128x128 fixed point number to 64.64 fixed point number
    /// @param x 128.128 unsigned fixed point number
    /// @return unsigned 64.64 unsigned fixed point number
    function from128x128(uint256 x) internal pure returns (uint128) {
        unchecked {
            uint256 answer = x >> 64;
            require(answer >= 0x0 && answer <= MAX_64x64);
            return uint128(answer);
        }
    }

    /// @notice helper to add two unsigened 128.128 fixed point numbers
    /// @param x 64.64 unsigned fixed point number
    /// @param y 64.64 unsigned fixed point number
    /// @return unsigned 64.64 unsigned fixed point number
    function add64x64(uint128 x, uint128 y) internal pure returns (uint128) {
        unchecked {
            uint256 answer = uint256(x) + y;
            require(answer <= MAX_64x64);
            return uint128(answer);
        }
    }

    /// @notice helper to subtract two unsigened 64.64 fixed point numbers
    /// @param x 64.64 signed fixed point number
    /// @param y 64.64 signed fixed point number
    /// @return unsigned 64.64 unsigned fixed point number
    function sub64x64U(int128 x, int128 y) internal pure returns (uint128) {
        unchecked {
            int256 result = int256(x) - y;
            require(result >= 0x0);
            require(uint256(result) <= MAX_64x64);
            return uint128(uint256(result));
        }
    }

    /// @notice helper to subtract two unsigened 64.64 fixed point numbers
    /// @param x 64.64 signed fixed point number
    /// @param y 64.64 signed fixed point number
    /// @return unsigned 64.64 unsigned fixed point number
    function sub64x64I(int128 x, int128 y) internal pure returns (int128) {
        unchecked {
            int256 result = int256(x) - y;
            require(result >= MIN_64x64_Signed);
            require(uint256(result) <= MAX_64x64);
            return int128(result);
        }
    }

    /// @notice helper function to multiply two unsigned 64.64 fixed point numbers
    /// @param x 64.64 unsigned fixed point number
    /// @param y 64.64 unsigned fixed point number
    /// @return unsigned
    function mul64x64(uint128 x, uint128 y) internal pure returns (uint128) {
        unchecked {
            uint256 answer = (uint256(x) * y) >> 64;
            require(answer <= MAX_64x64, "here you hit");
            return uint128(answer);
        }
    }

    /// @notice helper function to divide two unsigned 64.64 fixed point numbers
    /// @param x 64.64 unsigned fixed point number
    /// @param y 64.64 unsigned fixed point number
    /// @return unsigned uint128 64.64 unsigned integer
    function div64x64(uint128 x, uint128 y) internal pure returns (uint128) {
        unchecked {
            require(y != 0);

            uint256 answer = (uint256(x) << 64) / y;

            require(answer <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            return uint128(answer);
        }
    }

    /// @notice helper to divide two unsigned integers
    /// @param x uint256 unsigned integer
    /// @param y uint256 unsigned integer
    /// @return unsigned 64.64 fixed point number
    function divuu(uint256 x, uint256 y) internal pure returns (uint128) {
        unchecked {
            require(y != 0);

            uint256 answer;

            if (x <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                answer = (x << 64) / y;
            else {
                uint256 msb = 192;
                uint256 xc = x >> 192;
                if (xc >= 0x100000000) {
                    xc >>= 32;
                    msb += 32;
                }
                if (xc >= 0x10000) {
                    xc >>= 16;
                    msb += 16;
                }
                if (xc >= 0x100) {
                    xc >>= 8;
                    msb += 8;
                }
                if (xc >= 0x10) {
                    xc >>= 4;
                    msb += 4;
                }
                if (xc >= 0x4) {
                    xc >>= 2;
                    msb += 2;
                }
                if (xc >= 0x2) msb += 1; // No need to shift xc anymore

                answer = (x << (255 - msb)) / (((y - 1) >> (msb - 191)) + 1);
                require(
                    answer <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
                    "overflow in divuu"
                );

                uint256 hi = answer * (y >> 128);
                uint256 lo = answer * (y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

                uint256 xh = x >> 192;
                uint256 xl = x << 64;

                if (xl < lo) xh -= 1;
                xl -= lo; // We rely on overflow behavior here
                lo = hi << 128;
                if (xl < lo) xh -= 1;
                xl -= lo; // We rely on overflow behavior here

                assert(xh == hi >> 128);

                answer += xl / y;
            }

            require(
                answer <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
                "overflow in divuu last"
            );
            return uint128(answer);
        }
    }

    /// @notice helper function to get the absolute value of a signed integer.
    /// @param x unsigned integer
    /// @return unsigned
    function abs(int256 x) internal pure returns (uint256) {
        unchecked {
            return x < 0 ? uint256(-x) : uint256(x);
        }
    }

    /// @notice helper to calculate binary exponent of 64.64 unsigned fixed point number
    /// @param x unsigned 64.64 fixed point number
    /// @return unsigend 64.64 fixed point number
    function exp_2(uint128 x) private pure returns (uint128) {
        unchecked {
            require(x < 0x400000000000000000); // Overflow

            uint256 answer = 0x80000000000000000000000000000000;

            if (x & 0x8000000000000000 > 0)
                answer = (answer * 0x16A09E667F3BCC908B2FB1366EA957D3E) >> 128;
            if (x & 0x4000000000000000 > 0)
                answer = (answer * 0x1306FE0A31B7152DE8D5A46305C85EDEC) >> 128;
            if (x & 0x2000000000000000 > 0)
                answer = (answer * 0x1172B83C7D517ADCDF7C8C50EB14A791F) >> 128;
            if (x & 0x1000000000000000 > 0)
                answer = (answer * 0x10B5586CF9890F6298B92B71842A98363) >> 128;
            if (x & 0x800000000000000 > 0)
                answer = (answer * 0x1059B0D31585743AE7C548EB68CA417FD) >> 128;
            if (x & 0x400000000000000 > 0)
                answer = (answer * 0x102C9A3E778060EE6F7CACA4F7A29BDE8) >> 128;
            if (x & 0x200000000000000 > 0)
                answer = (answer * 0x10163DA9FB33356D84A66AE336DCDFA3F) >> 128;
            if (x & 0x100000000000000 > 0)
                answer = (answer * 0x100B1AFA5ABCBED6129AB13EC11DC9543) >> 128;
            if (x & 0x80000000000000 > 0)
                answer = (answer * 0x10058C86DA1C09EA1FF19D294CF2F679B) >> 128;
            if (x & 0x40000000000000 > 0)
                answer = (answer * 0x1002C605E2E8CEC506D21BFC89A23A00F) >> 128;
            if (x & 0x20000000000000 > 0)
                answer = (answer * 0x100162F3904051FA128BCA9C55C31E5DF) >> 128;
            if (x & 0x10000000000000 > 0)
                answer = (answer * 0x1000B175EFFDC76BA38E31671CA939725) >> 128;
            if (x & 0x8000000000000 > 0)
                answer = (answer * 0x100058BA01FB9F96D6CACD4B180917C3D) >> 128;
            if (x & 0x4000000000000 > 0)
                answer = (answer * 0x10002C5CC37DA9491D0985C348C68E7B3) >> 128;
            if (x & 0x2000000000000 > 0)
                answer = (answer * 0x1000162E525EE054754457D5995292026) >> 128;
            if (x & 0x1000000000000 > 0)
                answer = (answer * 0x10000B17255775C040618BF4A4ADE83FC) >> 128;
            if (x & 0x800000000000 > 0)
                answer = (answer * 0x1000058B91B5BC9AE2EED81E9B7D4CFAB) >> 128;
            if (x & 0x400000000000 > 0)
                answer = (answer * 0x100002C5C89D5EC6CA4D7C8ACC017B7C9) >> 128;
            if (x & 0x200000000000 > 0)
                answer = (answer * 0x10000162E43F4F831060E02D839A9D16D) >> 128;
            if (x & 0x100000000000 > 0)
                answer = (answer * 0x100000B1721BCFC99D9F890EA06911763) >> 128;
            if (x & 0x80000000000 > 0)
                answer = (answer * 0x10000058B90CF1E6D97F9CA14DBCC1628) >> 128;
            if (x & 0x40000000000 > 0)
                answer = (answer * 0x1000002C5C863B73F016468F6BAC5CA2B) >> 128;
            if (x & 0x20000000000 > 0)
                answer = (answer * 0x100000162E430E5A18F6119E3C02282A5) >> 128;
            if (x & 0x10000000000 > 0)
                answer = (answer * 0x1000000B1721835514B86E6D96EFD1BFE) >> 128;
            if (x & 0x8000000000 > 0)
                answer = (answer * 0x100000058B90C0B48C6BE5DF846C5B2EF) >> 128;
            if (x & 0x4000000000 > 0)
                answer = (answer * 0x10000002C5C8601CC6B9E94213C72737A) >> 128;
            if (x & 0x2000000000 > 0)
                answer = (answer * 0x1000000162E42FFF037DF38AA2B219F06) >> 128;
            if (x & 0x1000000000 > 0)
                answer = (answer * 0x10000000B17217FBA9C739AA5819F44F9) >> 128;
            if (x & 0x800000000 > 0)
                answer = (answer * 0x1000000058B90BFCDEE5ACD3C1CEDC823) >> 128;
            if (x & 0x400000000 > 0)
                answer = (answer * 0x100000002C5C85FE31F35A6A30DA1BE50) >> 128;
            if (x & 0x200000000 > 0)
                answer = (answer * 0x10000000162E42FF0999CE3541B9FFFCF) >> 128;
            if (x & 0x100000000 > 0)
                answer = (answer * 0x100000000B17217F80F4EF5AADDA45554) >> 128;
            if (x & 0x80000000 > 0)
                answer = (answer * 0x10000000058B90BFBF8479BD5A81B51AD) >> 128;
            if (x & 0x40000000 > 0)
                answer = (answer * 0x1000000002C5C85FDF84BD62AE30A74CC) >> 128;
            if (x & 0x20000000 > 0)
                answer = (answer * 0x100000000162E42FEFB2FED257559BDAA) >> 128;
            if (x & 0x10000000 > 0)
                answer = (answer * 0x1000000000B17217F7D5A7716BBA4A9AE) >> 128;
            if (x & 0x8000000 > 0)
                answer = (answer * 0x100000000058B90BFBE9DDBAC5E109CCE) >> 128;
            if (x & 0x4000000 > 0)
                answer = (answer * 0x10000000002C5C85FDF4B15DE6F17EB0D) >> 128;
            if (x & 0x2000000 > 0)
                answer = (answer * 0x1000000000162E42FEFA494F1478FDE05) >> 128;
            if (x & 0x1000000 > 0)
                answer = (answer * 0x10000000000B17217F7D20CF927C8E94C) >> 128;
            if (x & 0x800000 > 0)
                answer = (answer * 0x1000000000058B90BFBE8F71CB4E4B33D) >> 128;
            if (x & 0x400000 > 0)
                answer = (answer * 0x100000000002C5C85FDF477B662B26945) >> 128;
            if (x & 0x200000 > 0)
                answer = (answer * 0x10000000000162E42FEFA3AE53369388C) >> 128;
            if (x & 0x100000 > 0)
                answer = (answer * 0x100000000000B17217F7D1D351A389D40) >> 128;
            if (x & 0x80000 > 0)
                answer = (answer * 0x10000000000058B90BFBE8E8B2D3D4EDE) >> 128;
            if (x & 0x40000 > 0)
                answer = (answer * 0x1000000000002C5C85FDF4741BEA6E77E) >> 128;
            if (x & 0x20000 > 0)
                answer = (answer * 0x100000000000162E42FEFA39FE95583C2) >> 128;
            if (x & 0x10000 > 0)
                answer = (answer * 0x1000000000000B17217F7D1CFB72B45E1) >> 128;
            if (x & 0x8000 > 0)
                answer = (answer * 0x100000000000058B90BFBE8E7CC35C3F0) >> 128;
            if (x & 0x4000 > 0)
                answer = (answer * 0x10000000000002C5C85FDF473E242EA38) >> 128;
            if (x & 0x2000 > 0)
                answer = (answer * 0x1000000000000162E42FEFA39F02B772C) >> 128;
            if (x & 0x1000 > 0)
                answer = (answer * 0x10000000000000B17217F7D1CF7D83C1A) >> 128;
            if (x & 0x800 > 0)
                answer = (answer * 0x1000000000000058B90BFBE8E7BDCBE2E) >> 128;
            if (x & 0x400 > 0)
                answer = (answer * 0x100000000000002C5C85FDF473DEA871F) >> 128;
            if (x & 0x200 > 0)
                answer = (answer * 0x10000000000000162E42FEFA39EF44D91) >> 128;
            if (x & 0x100 > 0)
                answer = (answer * 0x100000000000000B17217F7D1CF79E949) >> 128;
            if (x & 0x80 > 0)
                answer = (answer * 0x10000000000000058B90BFBE8E7BCE544) >> 128;
            if (x & 0x40 > 0)
                answer = (answer * 0x1000000000000002C5C85FDF473DE6ECA) >> 128;
            if (x & 0x20 > 0)
                answer = (answer * 0x100000000000000162E42FEFA39EF366F) >> 128;
            if (x & 0x10 > 0)
                answer = (answer * 0x1000000000000000B17217F7D1CF79AFA) >> 128;
            if (x & 0x8 > 0)
                answer = (answer * 0x100000000000000058B90BFBE8E7BCD6D) >> 128;
            if (x & 0x4 > 0)
                answer = (answer * 0x10000000000000002C5C85FDF473DE6B2) >> 128;
            if (x & 0x2 > 0)
                answer = (answer * 0x1000000000000000162E42FEFA39EF358) >> 128;
            if (x & 0x1 > 0)
                answer = (answer * 0x10000000000000000B17217F7D1CF79AB) >> 128;

            answer >>= uint256(63 - (x >> 64));
            require(answer <= uint256(MAX_64x64));

            return uint128(uint256(answer));
        }
    }

    /// @notice helper to compute the square root of an unsigned uint256 integer
    /// @param x unsigned uint256 integer
    /// @return unsigned 64.64 unsigned fixed point number
    function sqrtu(uint256 x) internal pure returns (uint128) {
        unchecked {
            if (x == 0) return 0;
            else {
                uint256 xx = x;
                uint256 r = 1;
                if (xx >= 0x100000000000000000000000000000000) {
                    xx >>= 128;
                    r <<= 64;
                }
                if (xx >= 0x10000000000000000) {
                    xx >>= 64;
                    r <<= 32;
                }
                if (xx >= 0x100000000) {
                    xx >>= 32;
                    r <<= 16;
                }
                if (xx >= 0x10000) {
                    xx >>= 16;
                    r <<= 8;
                }
                if (xx >= 0x100) {
                    xx >>= 8;
                    r <<= 4;
                }
                if (xx >= 0x10) {
                    xx >>= 4;
                    r <<= 2;
                }
                if (xx >= 0x8) {
                    r <<= 1;
                }
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1; // Seven iterations should be enough
                uint256 r1 = x / r;
                return uint128(r < r1 ? r : r1);
            }
        }
    }

    //==============================================================Uniswap V2 Standard Helpers===================================================

    ///@notice helper to calculate the spot price of token0 in a v2 pool represented as 64.64 fixed point.
    ///@param reserve0 The token0 reserves in the pool.
    ///@param reserve1 The token1 reserves in the pool.
    ///@param decimals0 The decimals of token0.
    ///@param decimals1 The decimals of token1.
    ///@return unsigned The spot price of token0 in 64.64 fixed point.
    function v2SpotPrice64x64(
        uint112 reserve0,
        uint112 reserve1,
        uint8 decimals0,
        uint8 decimals1
    ) internal pure returns (uint128) {
        int8 shift = int8(decimals0) - int8(decimals1);
        uint128 spotPrice = divuu(uint256(reserve1), uint256(reserve0));
        ///@notice Adjust the spot price by decimals0-decimals1
        uint128 normalizedSpot = shift < 0
            ? spotPrice / (uint128(10)**uint8(-shift))
            : spotPrice * (uint128(10)**uint8(shift));
        return normalizedSpot;
    }

    ///@notice helper to normalize two v2 reserves to a target decimal.
    ///@param _reserve0 The token0 reserves in the pool.
    ///@param _reserve1 The token1 reserves in the pool.
    ///@param decimals0 The decimals of token0.
    ///@param decimals1 The decimals of token1.
    ///@param _targetDecimals The target decimals to which the output reserves will be normalized.
    function v2NormalizeReserves(
        uint112 _reserve0,
        uint112 _reserve1,
        uint8 decimals0,
        uint8 decimals1,
        uint8 _targetDecimals
    ) internal pure returns (uint112 reserve0, uint112 reserve1) {
        int8 shift0 = int8(_targetDecimals) - int8(decimals0);
        int8 shift1 = int8(_targetDecimals) - int8(decimals1);

        reserve0 = shift0 < 0
            ? _reserve0 / uint112(10)**uint8(-shift0)
            : _reserve0 * uint112(10)**uint8(shift0);
        reserve1 = shift1 < 0
            ? _reserve1 / uint112(10)**uint8(-shift1)
            : _reserve0 * uint112(10)**uint8(shift1);
    }

    //==============================================================Uniswap V3 Standard Helpers===================================================

    ///@notice Function to convers a SqrtPrice Q96.64 fixed point to Price as 64.64 fixed point resolution.
    ///@dev token0 is token0 on the pool, and token1 is token1 on the pool. Not tokenIn,tokenOut on the swap.
    ///@param decimals0 Token0 in the pool.
    ///@param decimals1 Token1 in the pool.
    ///@param sqrtPriceX96 The slot0 sqrtPriceX96 on the pool.
    ///@param token0IsReserve0 Bool indicating whether the tokenIn to be quoted is token0 on the pool.
    ///@return priceX64 The spot price of TokenIn as 64.64 fixed point.
    function fromSqrtX96ToX64(
        uint8 decimals0,
        uint8 decimals1,
        uint160 sqrtPriceX96,
        bool token0IsReserve0
    ) internal pure returns (uint128 priceX64) {
        unchecked {
            ///@notice Cache the difference between the input and output token decimals. p=y/x ==> p*10**(x_decimals-y_decimals)>>Q192 will be the proper price in base 10.
            int8 decimalShift = int8(decimals0) - int8(decimals1);
            ///@notice Square the sqrtPrice ratio and normalize the value based on decimalShift.
            uint256 priceSquaredX96 = decimalShift < 0
                ? uint256(sqrtPriceX96)**2 / uint256(10)**(uint8(-decimalShift))
                : uint256(sqrtPriceX96)**2 * 10**uint8(decimalShift);

            ///@notice The first value is a Q96 representation of p_token0, the second is 128X fixed point representation of p_token1.
            uint256 priceSquaredShiftQ96 = token0IsReserve0
                ? priceSquaredX96 / Q96
                : (Q96 * 0xffffffffffffffffffffffffffffffff) /
                    (priceSquaredX96 / Q96);

            ///@notice Convert the first value to 128X fixed point by shifting it left 128 bits and normalizing the value by Q96.
            uint256 priceX128 = token0IsReserve0
                ? (uint256(priceSquaredShiftQ96) *
                    0xffffffffffffffffffffffffffffffff) / Q96
                : priceSquaredShiftQ96;
            ///@notice Right shift 64 bits to convert to 64.64 fixed point form.
            priceX64 = uint128(priceX128 >> 64);

            ///@notice Ensure priceX64 hasn't overflowed.
            require(priceX64 <= type(uint128).max, "Shadow overflow");
        }
    }

    ///@notice Helper to convert a 64.64 fixed point spot price into a valid sqrtRatioX96 on a v3 pool.
    ///@param decimals0 Token0 decimals in the pool.
    ///@param decimals1 Token1 decimals in the pool.
    ///@param spot64X The spot price in 64.64 fixed point form.
    ///@param zeroForOne Bool indicating whether the spot64X is quoting the input or the output token.
    ///@return sqrtRatioX96 The sqrtRatioX96 in the unnormalized form as stored in the v3 pool. i.e. sqrt(y/x).
    function from64XSpotToSqrtRatioX96(
        uint8 decimals0,
        uint8 decimals1,
        uint128 spot64X,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtRatioX96) {
        ///@notice Cache the difference between the input and output token decimals. p=y/x ==> p*10**(x_decimals-y_decimals)>>Q192 will be the proper price in base 10.
        int8 shift = int8(decimals0) - int8(decimals1);
        ///@notice Convert to Quad floating point representation, i.e. IEEE 754 form.
        bytes16 spotQuad = QuadruplePrecision.from64x64(int128(spot64X));
        ///@notice Take the square root of the spotPrice.
        bytes16 sqrtSpotQuad = QuadruplePrecision.sqrt(spotQuad);
        unchecked {
            ///@notice Unnormalize based on shift to convert into the spot price as represented in the v3 pool.
            sqrtRatioX96 = shift < 0
                ? uint160(
                    (int160(QuadruplePrecision.to64x64(sqrtSpotQuad)) << 32) /
                        (-shift)
                )
                : uint160(
                    (int160(QuadruplePrecision.to64x64(sqrtSpotQuad)) << 32) *
                        shift
                );
            ///@notice Ensure we haven't overflowed.
            require(sqrtRatioX96 <= Q96);
            if (!zeroForOne) {
                ///@notice Take the inverse if zeroForOne is false.
                sqrtRatioX96 = uint160(FullMath.mulDiv(1, Q96, sqrtRatioX96));
                ///@notice Ensure we haven't overflowed.
                require(sqrtRatioX96 <= Q96);
            }
        }
    }

    //===============================================================CFMM Helpers==================================================================

    ///@notice helper to calculate the proportional relationship difference between two spot prices.
    ///@dev Note this formula calculates abs(1-(x/y))
    ///@param x 64.64 fixed point number.
    ///@param y 64.64 fixed point number.
    ///@return unsigned 64.64 fixed point number. The proportional difference between two numbers.
    function proportionalPriceDifferenceUnsigned(uint128 x, uint128 y)
        internal
        pure
        returns (uint128)
    {
        ///@notice If e
        if (x == 0 && !(y == 0)) {
            return ONE_64x64;
        }
        ///@notice If y is zero and x is not return 1.
        if (y == 0 && !(x == 0)) {
            return ONE_64x64;
        }
        if (y == x) {
            return 0;
        }
        ///@notice will always be >-0
        uint128 proportion = x > y
            ? sub64x64U(int128(div64x64(x, y)), int128(ONE_64x64))
            : sub64x64U(int128(div64x64(y, x)), int128(ONE_64x64));

        return proportion;
    }

    ///@notice helper to calculate the proportional relationship difference between two spot prices.
    ///@dev Note this formula calculates 1-(x/y)
    ///@param x 64.64 fixed point number.
    ///@param y 64.64 fixed point number.
    ///@return nsigned 64.64 fixed point number. The proportional difference between two numbers.
    function proportionalPriceDifferenceSigned(uint128 x, uint128 y)
        internal
        pure
        returns (int128)
    {
        ///@notice If e
        if (x == 0 && !(y == 0)) {
            return int128(ONE_64x64);
        }
        ///@notice If y is zero and x is not return 1.
        if (y == 0 && !(x == 0)) {
            return int128(ONE_64x64);
        }
        if (y == x) {
            return 0;
        }
        ///@notice will always be >-0
        int128 proportion = sub64x64I(
            int128(div64x64(x, y)),
            int128(ONE_64x64)
        );

        return proportion;
    }
}
