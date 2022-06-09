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
    address public marketPairAddressBUSD = address(0xdd52bd6CcE78f3114ba83B04F006aec03f432779); // CHANGE THIS

    uint256 public PERIOD = 10 minutes;
    uint32 public blockTimestampLast;

    uint256 public PSTN_BUSD_price0CumulativeLast;
    uint256 public PSTN_BUSD_price1CumulativeLast;

    FixedPoint.uq112x112 public PSTN_BUSD_price0Average;
    FixedPoint.uq112x112 public PSTN_BUSD_price1Average;

    constructor() {
        owner = msg.sender;

        // PISTON/BUSD
        PSTN_BUSD_price0CumulativeLast = IUniswapV2Pair(marketPairAddressBUSD).price0CumulativeLast();
        PSTN_BUSD_price1CumulativeLast = IUniswapV2Pair(marketPairAddressBUSD).price1CumulativeLast();

        (, , blockTimestampLast) = IUniswapV2Pair(marketPairAddressBUSD).getReserves();
    }

    function setup(address aam_pstn_busd) external {
        require(msg.sender == owner, "owner only");
        require( aam_pstn_busd != address(0) );

        marketPairAddressBUSD = aam_pstn_busd;
    }
    
    function setOwner(address value) external {
        require(msg.sender == owner, "owner only");
        require(value != address(0));
        owner = value;
    }

    //  legacy alias
    //
    function getPrice(uint amount) external view returns(uint) {
        return getPriceTWAP(amount);
    }

    // price BUSD only calculated by TWAP (Time Weighted Average Price)
    // use this if you need to store the price
    // flash loan safe
    function getPriceTWAP(uint amountIn) public view returns (uint amountOut) {
        amountOut = PSTN_BUSD_price0Average.mul(amountIn.mul(1 ether)).decode144();
    }

    // update TWAP price. this is called several times from other contracts to have actual values.
    function updateTWAP() external {

        //  PISTON/BUSD
        //------------------------------------------------------------
        (uint PSTN_BUSD_price0Cumulative, uint PSTN_BUSD_price1Cumulative, uint32 PSTN_BUSD_blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(marketPairAddressBUSD));
        uint32 timeElapsed = PSTN_BUSD_blockTimestamp - blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        require(timeElapsed >= PERIOD, 'PistonPriceFeed: PERIOD_NOT_ELAPSED');

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        PSTN_BUSD_price0Average = FixedPoint.uq112x112(uint224((PSTN_BUSD_price0Cumulative - PSTN_BUSD_price0CumulativeLast) / timeElapsed));
        PSTN_BUSD_price1Average = FixedPoint.uq112x112(uint224((PSTN_BUSD_price1Cumulative - PSTN_BUSD_price1CumulativeLast) / timeElapsed));

        PSTN_BUSD_price0CumulativeLast = PSTN_BUSD_price0Cumulative;
        PSTN_BUSD_price1CumulativeLast = PSTN_BUSD_price1Cumulative;

        blockTimestampLast = PSTN_BUSD_blockTimestamp;
    }

    function needsUpdateTWAP() external view returns (bool){
        (, , uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(marketPairAddressBUSD));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;

        return timeElapsed >= PERIOD;
    }

    function update_PERIOD(uint256 value) external {
        require(msg.sender == owner, "only owner");

        PERIOD = value;
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
