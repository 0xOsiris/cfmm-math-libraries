// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../../../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../../../lib/interfaces/token/IERC20.sol";
import "./Console.sol";

contract SwapV3 {

    uint256 uniV3AmountReceived;

    function swapV3(
        address _lp,
        bool _zeroForOne,
        address _tokenIn,
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint160 _sqrtPriceLimitX96,
        address _reciever
    ) external returns (uint256 amountRecieved) {
        
        ///@notice Pack the relevant data to be retrieved in the swap callback.
        bytes memory data = abi.encode(
            _amountOutMin,
            _zeroForOne,
            _tokenIn,
            _lp,
            msg.sender
        );
        console.log(IERC20(_tokenIn).balanceOf(address(this)));

        ///@notice Initialize Storage variable uniV3AmountOut to 0 prior to the swap.
        uniV3AmountReceived = 0;

        ///@notice Execute the swap on the lp for the amounts specified.
        IUniswapV3Pool(_lp).swap(
            _reciever,
            _zeroForOne,
            int256(_amountIn),
            _sqrtPriceLimitX96,
            data
        );

        ///@notice Return the amountOut yielded from the swap.
        return uniV3AmountReceived;
    }

    ///@notice Uniswap V3 callback function called during a swap on a v3 liqudity pool.
    ///@param amount0Delta - The change in token0 reserves from the swap.
    ///@param amount1Delta - The change in token1 reserves from the swap.
    ///@param data - The data packed into the swap.
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory data
    ) external {
        ///@notice Decode all of the swap data.
        (
            uint256 amountOutMin,
            bool _zeroForOne,
            address tokenIn,
            address poolAddress,
            address _sender
        ) = abi.decode(
                data,
                (uint256, bool, address, address,address)
            );


        ///@notice If swapping token0 for token1.
        if (_zeroForOne) {
            ///@notice Set contract storage variable to the amountOut from the swap.
            uniV3AmountReceived = uint256(-amount1Delta);

            ///@notice If swapping token1 for token0.
        } else {
            ///@notice Set contract storage variable to the amountOut from the swap.
            uniV3AmountReceived = uint256(-amount0Delta);
        }

        ///@notice Require the amountOut from the swap is greater than or equal to the amountOutMin.
        require(uniV3AmountReceived>= amountOutMin, "Insufficient output");

        ///@notice Set amountIn to the amountInDelta depending on boolean zeroForOne.
        uint256 amountIn = _zeroForOne
            ? uint256(amount0Delta)
            : uint256(amount1Delta);

        
        ///@notice Transfer the amountIn of tokenIn to the liquidity pool from the sender.
        IERC20(tokenIn).transfer(poolAddress, amountIn);
               
    }

    receive() external payable {}
}