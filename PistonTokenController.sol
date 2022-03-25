// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./libs/IUniswapV2Pair.sol";
import "./libs/IUniswapV2Factory.sol";
import "./libs/IUniswapV2Router.sol";

contract PistonTokenController is Initializable, ERC20Upgradeable, OwnableUpgradeable {
	using SafeMathUpgradeable for uint256;
	
	
	//address private constant BUSD = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56); //BUSD mainnet
	address private constant BUSD =	address(0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7); //BUSD testnet
	
	address public constant deadWallet = 0x000000000000000000000000000000000000dEaD; 
	
	IUniswapV2Router02 public  uniswapV2Router;
	address public  uniswapV2Pair;
	
	IToken private pistonToken;
	
	uint256 public liquidityPercent;
	uint256 public burnPercent;
	uint256 public marketingDevPercent;
	uint256 public racePercent;
	address public _ecosystemWalletAddress;
	address public _raceContractAddress;
	
	uint256 public swapTokensAtAmount;
	
	function initialize(address _Piston) public virtual initializer {
	
		__Ownable_init();
	
		pistonToken = IToken(address(_Piston));
		
		//IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // mainnet
		IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3); // testnet
		 
		// Create a uniswap pair for this new token
		uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(pistonToken), BUSD);
		//.getPair(address(pistonToken), BUSD);
		
		// set the rest of the contract variables
		uniswapV2Router = _uniswapV2Router;
		
		
		liquidityPercent = 20; // 20% of all the fees
		burnPercent = 10; // 10% of all the fees
		marketingDevPercent = 30; // 30% of all the fees
		racePercent = 40; // 40% of all the fees 
	}
	
	function setSwapTokensAtAmount(uint256 amount) external onlyOwner{
		swapTokensAtAmount = amount * 10**18;
	}
	
	function setContracts(address ecosystemWalletAddress, address raceContractAddress) external onlyOwner {
		_ecosystemWalletAddress = ecosystemWalletAddress;
		_raceContractAddress = raceContractAddress;
	}
	
	function swapAndLiquify()  external onlyOwner  {
	
		uint256 forLiquidity = pistonToken.balanceOf(address(this)).mul(liquidityPercent).div(100);
		uint256 forBurn = pistonToken.balanceOf(address(this)).mul(burnPercent).div(100);
		uint256 forEcosystem = pistonToken.balanceOf(address(this)).mul(marketingDevPercent).div(100);
			
		if ( forLiquidity >= swapTokensAtAmount) {
		
			uint256 half = forLiquidity.div(2);
			uint256 otherHalf = forLiquidity.sub(half);
			
			uint256 initialBalance = IERC20Upgradeable(BUSD).balanceOf(address(this));			
			swapTokensForBUSD(half);			
			uint256 newBalance = IERC20Upgradeable(BUSD).balanceOf(address(this)).sub(initialBalance);
			
			// liquidityPercent 20% goes to pancakeswap
			addLiquidity(otherHalf, newBalance);
			
			// send 30% to  _ecosystemWalletAddress after BUSD conversion
			swapTokensForBUSD(forEcosystem);			
			IERC20Upgradeable(BUSD).transfer(_ecosystemWalletAddress, IERC20Upgradeable(BUSD).balanceOf(address(this)));
			
			// send 10% to burn
			pistonToken.transfer(deadWallet, forBurn);			
			
			//remaining tokens to race contract - around 40%
			pistonToken.transfer(_raceContractAddress, pistonToken.balanceOf(address(this)));
			
			
		}
	}
	
	function swapTokensForBUSD(uint256 tokenAmount) private  {
	
		address[] memory path = new address[](2);
		path[0] = address(pistonToken);
		path[1] = BUSD;
		
		pistonToken.approve(address(uniswapV2Router), tokenAmount);
			// make the swap
			uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
			tokenAmount,
			0,
			path,
			address(this),
			block.timestamp.add(3600)
		);
	}
	
	function addLiquidity(uint256 tokenAmount, uint256 busdAmount) private {
		
		pistonToken.approve(address(uniswapV2Router), tokenAmount);		
		IERC20Upgradeable(BUSD).approve(address(uniswapV2Router), busdAmount);
		
		// add the liquidity
		uniswapV2Router.addLiquidity(
			address(pistonToken),
			BUSD,
			tokenAmount,
			busdAmount,
			0,
			0,
			owner(), //address(this),
			block.timestamp
		);
	}
	
	
	
	
	/* getters */
	function pistonBalance() public view  returns (uint256, uint256, uint256) {
		return (pistonToken.balanceOf(address(this)), IERC20Upgradeable(BUSD).balanceOf(address(this)), pistonToken.balanceOf(address(this)).mul(liquidityPercent).div(100));
	}
	
	function getPairBalance() public view  returns (uint256, uint256) {
		return (pistonToken.balanceOf(address(uniswapV2Pair)), IERC20Upgradeable(BUSD).balanceOf(address(uniswapV2Pair)));
	}
	
	function getTokenAndControllerAddress() public view  returns (address, address) {
		return (address(pistonToken), address(this) );
	}
	

	
	
}

interface IToken {

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender)
    external
    view
    returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);
}
