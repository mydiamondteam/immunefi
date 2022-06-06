// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import '@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol';

contract PriceFeed {

    using SafeMath for uint256;
    using FixedPoint for *;

    address owner;
    address public marketPairAddressBUSD = address(0xdd52bd6CcE78f3114ba83B04F006aec03f432779); // CHANGE THIS!!! 
    address public marketPairAddressBNB = address(0xD9f0D34f142E4C855D879A84195CaEeA4fcf6E4B); // CHANGE THIS!!! 
    address public marketPairAddressBNB_BUSD = address(0x58F876857a02D6762E0101bb5C46A8c1ED44Dc16); // CHANGE THIS!!! 

    IERC20 public pistonToken = IERC20(address(0xBfACD29427fF376FF3BC22dfFB29866277cA5Fb4)); // CHANGE THIS!!! 
    IERC20 public busdtoken = IERC20(address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56)); // MAINNET BUSD 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56  TESTNET BUSD 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7
    IERC20 public bnbtoken = IERC20(address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c)); // MAINNET WBNB 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c  TESTNET BUSD 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd

    uint256 public constant PERIOD = 10 minutes;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;

    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    constructor() {
        owner = msg.sender;

        // TWAP setup
        price0CumulativeLast = IUniswapV2Pair(marketPairAddressBUSD).price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = IUniswapV2Pair(marketPairAddressBUSD).price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = IUniswapV2Pair(marketPairAddressBUSD).getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'PistonPriceFeed: NO_RESERVES'); // ensure that there's liquidity in the pair
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

        pistonToken = IERC20(piston_token); 
        busdtoken = IERC20(busd_token); 
        bnbtoken = IERC20(bnb_token); 
    }
    
    function setOwner(address value) external {
        require(msg.sender == owner, "owner only");
        require(value != address(0));
        owner = value;
    }

    //  Market Data 
    //
    function getPrice(uint amount) external view returns(uint) {
        return getPriceTWAP(address(pistonToken), amount.mul(1 ether));
    }

    // price BUSD only calculated by TWAP (Time Weighted Average Price)
    // use this if you need to store the price
    // flash loan safe
    function getPriceTWAP(address token, uint amountIn) public view returns (uint amountOut) {
        if (token == address(pistonToken)) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == address(busdtoken), 'PistonPriceFeed: INVALID_TOKEN');
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }

    // live price by Pair reserves (DONT STORE THIS!)
    function getPriceByReserves(uint amount) external view returns(uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(marketPairAddressBUSD);
        IERC20 token0 = IERC20(pair.token0());
        (uint Res0, uint Res1,) = pair.getReserves();

        // decimals
        uint _Res1 = Res1*(10**token0.decimals());
        uint _Res0 = Res0;
        
        return ((amount*_Res1)/_Res0);
    }

    // live price BUSD pair (DONT STORE THIS!)
    function getPriceByBalancesBUSD() public view returns(uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(marketPairAddressBUSD);      

        // decimals
        uint _Res0 = pistonToken.balanceOf(address(pair));
        uint _Res1 = busdtoken.balanceOf(address(pair));        
        
        return ((_Res1*10**18)/_Res0);
    }

    //live price BNB pair (DONT STORE THIS!)
    function getPriceByBalancesBNB() public view returns(uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(marketPairAddressBNB); 

        // decimals
        uint _Res0 = pistonToken.balanceOf(address(pair));
        uint _Res1 = bnbtoken.balanceOf(address(pair));        
        
        return ((_Res1*10**18)/_Res0);
    }

    // live price BNB token (DONT STORE THIS!)
    function getBNBPrice() public view returns(uint) {
        IUniswapV2Pair pair = IUniswapV2Pair(marketPairAddressBNB_BUSD); 

        // decimals
        uint _Res0 = busdtoken.balanceOf(address(pair));
        uint _Res1 = bnbtoken.balanceOf(address(pair));        
        
        return ((_Res0*10**18)/_Res1);
    }

    // live avg price PISTON/BUSD and PISTON/BNB (DONT STORE THIS!)
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

    // update TWAP price. this is called several times from oether contracts to have actual values.
    function updateTWAP() external {
        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(marketPairAddressBUSD));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        require(timeElapsed >= PERIOD, 'PistonPriceFeed: PERIOD_NOT_ELAPSED');

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    function needsUpdateTWAP() external view returns (bool){
        (, , uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(marketPairAddressBUSD));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        return timeElapsed >= PERIOD;
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

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function decimals() external view returns (uint8);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);


}
