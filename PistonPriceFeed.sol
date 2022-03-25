// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./libs/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PistonPriceFeed {

    address owner;
    address marketPairAddress;

    constructor() {
        owner = msg.sender;
    }

    function setMarketPair(address value) external {
        require(msg.sender == owner, "owner only");
        marketPairAddress = value;
    }
    
    function setOwner(address value) external {
        require(msg.sender == owner, "owner only");
        owner = value;
    }

    //  Market Data 
    //
    function getPrice(uint amount) external view returns(uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(marketPairAddress);
        ERC20 token0 = ERC20(pair.token0());
        (uint Res0, uint Res1,) = pair.getReserves();

        // decimals
        uint _Res1 = Res1;
        uint _Res0 = Res0*(10**token0.decimals());
        
        return ((amount*_Res0)/_Res1);
    }
}
    
