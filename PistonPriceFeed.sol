// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./libs/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PistonPriceFeed {

    using SafeMath for uint256;

    address owner;
    address public marketPairAddressBUSD = address(0); // CHANGE THIS!!! TEST 0xE11e74De5a349BF6746E085e4E94ea5dDA83C7A8
    address public marketPairAddressBNB = address(0); // CHANGE THIS!!! TEST 0x6120F2d2f2021264eA9E7F3e242c9bf74048b31c
    address public marketPairAddressBNB_BUSD = address(0); // CHANGE THIS!!! TEST 0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16

    ERC20 public pistonToken = ERC20(address(0)); // CHANGE THIS!!! test 0x911fb531944D0b6eC6270d59FC0821bCc104eEb4
    ERC20 public busdtoken = ERC20(address(0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7)); // MAINNET BUSD 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56  TESTNET BUSD 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7
    ERC20 public bnbtoken = ERC20(address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd)); // MAINNET WBNB 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c  TESTNET BUSD 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd

    constructor() {
        owner = msg.sender;
    }

    function setup(address piston_token, address busd_token, address bnb_token, address aam_pstn_busd, address aam_pstn_bnb, address aam_bnb_busd) external {
        require(msg.sender == owner, "owner only");
        require(piston_token != address(0) && 
            busd_token != address(0) && 
            bnb_token != address(0) && 
            aam_pstn_busd != address(0) && 
            aam_pstn_bnb != address(0) && 
            aam_bnb_busd != address(0)
        );

        marketPairAddressBUSD = aam_pstn_busd;
        marketPairAddressBNB = aam_pstn_bnb;
        marketPairAddressBNB_BUSD = aam_bnb_busd;

        pistonToken = ERC20(piston_token); 
        busdtoken = ERC20(busd_token); 
        bnbtoken = ERC20(bnb_token); 
    }
    
    function setOwner(address value) external {
        require(msg.sender == owner, "owner only");
        require(value != address(0));
        owner = value;
    }

    //  Market Data 
    //
    function getPrice(uint amount) external view returns(uint) {
        return getPriceAverage() * amount;
    }

    function getPriceByReserves(uint amount) external view returns(uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(marketPairAddressBUSD);
        ERC20 token0 = ERC20(pair.token0());
        (uint Res0, uint Res1,) = pair.getReserves();

        // decimals
        uint _Res1 = Res1*(10**token0.decimals());
        uint _Res0 = Res0;
        
        return ((amount*_Res1)/_Res0);
    }

    function getPriceByBalancesBUSD() public view returns(uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(marketPairAddressBUSD);      

        // decimals
        uint _Res0 = pistonToken.balanceOf(address(pair));
        uint _Res1 = busdtoken.balanceOf(address(pair));        
        
        return ((_Res1*10**18)/_Res0);
    }

    function getPriceByBalancesBNB() public view returns(uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(marketPairAddressBNB); 

        // decimals
        uint _Res0 = pistonToken.balanceOf(address(pair));
        uint _Res1 = bnbtoken.balanceOf(address(pair));        
        
        return ((_Res1*10**18)/_Res0);
    }

    function getBNBPrice() public view returns(uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(marketPairAddressBNB_BUSD); 

        // decimals
        uint _Res0 = busdtoken.balanceOf(address(pair));
        uint _Res1 = bnbtoken.balanceOf(address(pair));        
        
        return ((_Res0*10**18)/_Res1);
    }

    function getPriceAverage() public view returns(uint) {

        uint256 pistonBalanceAtBUSDPAIR = pistonToken.balanceOf(address(marketPairAddressBUSD));
        uint256 pistonBalanceAtBNBPAIR = pistonToken.balanceOf(address(marketPairAddressBNB));

        uint256 PSTNPriceAtBUSDPair = getPriceByBalancesBUSD();
        uint256 PSTNPriceAtBNBPair = getPriceByBalancesBNB();

        return pistonBalanceAtBUSDPAIR.mul(PSTNPriceAtBUSDPair).add(
                pistonBalanceAtBNBPAIR.mul(PSTNPriceAtBNBPair).mul(getBNBPrice().div(1 ether))            
            ).div(pistonBalanceAtBUSDPAIR.add(pistonBalanceAtBNBPAIR)
        );
    }
}
    

    /**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
    /**
     * @dev Multiplies two numbers, throws on overflow.
   */
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
     * @dev Integer division of two numbers, truncating the quotient.
   */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        // uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return a / b;
    }

    /**
     * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
   */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /* @dev Subtracts two numbers, else returns zero */
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b > a) {
            return 0;
        } else {
            return a - b;
        }
    }

    /**
     * @dev Adds two numbers, throws on overflow.
   */
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
