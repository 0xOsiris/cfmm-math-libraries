// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../../lib/interfaces/token/IWETH.sol";

contract Swap {
    address wnato;

    IUniswapV2Router02 uniV2Router;

    constructor(address uniV2Addr, address _wnato) {
        wnato = _wnato;
        uniV2Router = IUniswapV2Router02(uniV2Addr);
    }

    ///@dev the msg.sender needs to have eth before calling this function
    function swapEthForTokenWithUniV2(uint256 amount, address _swapToken)
        public
        returns (uint256)
    {
        //set the path
        address[] memory path = new address[](2);
        path[0] = wnato;
        path[1] = _swapToken;

        // swap eth for tokens
        uint256 amountOut = uniV2Router.swapExactETHForTokens{value: amount}(
            1,
            path,
            msg.sender,
            (2**256 - 1)
        )[1];

        return amountOut;
    }

    ///@dev the msg.sender needs to have eth before calling this function
    function swapEthForTokenWithTransferFeesUniV2(uint256 amount, address _swapToken)
        public
        
    {
        //set the path
        address[] memory path = new address[](2);
        path[0] = wnato;
        path[1] = _swapToken;

        // swap eth for tokens
        uniV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value:amount}(1, path, msg.sender, (2**256 - 1));
        
    }
}
