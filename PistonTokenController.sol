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
	
	
	address private constant BUSD = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56); //BUSD mainnet
	
	address public constant deadWallet = 0x000000000000000000000000000000000000dEaD; 
	
	IUniswapV2Router02 public  uniswapV2Router;
	address public  uniswapV2Pair;
	
	IToken private pistonToken;
	
	uint256 public liquidityPercent;
	uint256 public burnPercent;
	uint256 public marketingDevPercent;
	uint256 public racePercent;
	address public _ecosystemWalletAddress;
    address public _liquidityWalletAddress;
	address public _raceContractAddress;
	
	uint256 public swapTokensAtAmount;
	
	uint256 public _maxTokens;
	
	//readers
	uint256 public tokensInTrap;
	address public trapWallet;
	
	
	function initialize(address _Piston) public virtual initializer {
	
		__Ownable_init();
	
		pistonToken = IToken(address(_Piston));
		
		IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // mainnet
		//IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3); // testnet
		 
		// Create a uniswap pair for this new token
		uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).getPair(address(pistonToken), BUSD);
		
		// set the rest of the contract variables
		uniswapV2Router = _uniswapV2Router;
		
		//Initial settings 
		liquidityPercent = 20; // 20% 
		burnPercent = 10; // 10% 
		marketingDevPercent = 10; // 10% 
		racePercent = 60; // 60% 
		
	}
	

	function setContracts(address ecosystemWalletAddress, address raceContractAddress) external onlyOwner {
		_ecosystemWalletAddress = ecosystemWalletAddress;
		_raceContractAddress = raceContractAddress;
	}
	
	function setMaxTokensForLiquify(uint256 maxTokens) external onlyOwner {
		 require(maxTokens <= 500, "hard cap 500");
		_maxTokens = maxTokens*10**18;
	}
	
	function setRatio(uint256 _liquidityPercent, uint256 _burnPercent, uint256 _marketingDevPercent, uint256 _racePercent) external onlyOwner {
	
		require(_liquidityPercent.add(_burnPercent).add(_marketingDevPercent).add(_racePercent) == 100, "total should be 100 percent");
	
		liquidityPercent = _liquidityPercent;
		burnPercent = _burnPercent;
		marketingDevPercent = _marketingDevPercent;
		racePercent = _racePercent;
	
	}
	
	function updateVariablesFromPistonToken() public onlyOwner{
		trapWallet=pistonToken.trapWallet();
	}
	
	function setTokensInTrapAsPerTokenContract(uint256 _amount) external onlyOwner {
		 tokensInTrap=_amount*10**18;
	}
	
	function swapAndLiquify()  external onlyOwner  {
	
		// total PSTN tokens to be handled: _maxTokens	
		
		uint256 forLiquidity = _maxTokens.mul(liquidityPercent).div(100);
		uint256 forBurn = _maxTokens.mul(burnPercent).div(100);
		uint256 forEcosystem = _maxTokens.mul(marketingDevPercent).div(100);
		uint256 forRace = _maxTokens.mul(racePercent).div(100);
		
		uint256 half = forLiquidity.div(2);
		uint256 otherHalf = forLiquidity.sub(half);
		
		uint256 initialBalance = IERC20Upgradeable(BUSD).balanceOf(address(this));			
		swapTokensForBUSD(half);			
		uint256 newBalance = IERC20Upgradeable(BUSD).balanceOf(address(this)).sub(initialBalance);
		
		// liquidityPercent (PSTN & BUSD half split)  goes to pancakeswap
		addLiquidity(otherHalf, newBalance);
		
		// send  forEcosystem PSTN tokens to  _ecosystemWalletAddress after BUSD conversion
		swapTokensForBUSD(forEcosystem);			
		IERC20Upgradeable(BUSD).transfer(_ecosystemWalletAddress, IERC20Upgradeable(BUSD).balanceOf(address(this)));
		
		// send forBurn PSTN tokens to deadwallet
		if(forBurn>0) {
			pistonToken.transfer(deadWallet, forBurn);			
		}
		
		// send forRace tokens to race contract
		pistonToken.transfer(_raceContractAddress, forRace);			
	
	}

	/**
		transfer amounts to new controller to handle the huge amount in small portions
	 */
	function transferToControllerV2(uint256 amount) external onlyOwner { // pls note amount is w/o 0s for 18 decimals
		require(amount <= 1000, "amount is to big");
		address controllerV2 = address(0x2c035E3960dd2E67f6ec6204c5BC55B203Ef82bF);
		require(pistonToken.transfer(controllerV2, amount*10**18), "transfer controller v2 failed" );
  	}
	
	function transfertoTrap(uint256 amount) external onlyOwner { // pls note amount is w/o 0s for 18 decimals
		// tokens from anti-bot trap top a wallet for community useage
		updateVariablesFromPistonToken();
		require(tokensInTrap > 0 && tokensInTrap > amount*10**18, "trap already clean");
		require(pistonToken.transfer(trapWallet, amount*10**18), "transfer to trap failed" );
		tokensInTrap -= amount*10**18;
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
			deadWallet, 
			block.timestamp
		);
	}	
	
	
/* getters */
	function getBalances() public view  returns (uint256, uint256) {
		return (pistonToken.balanceOf(address(this)), IERC20Upgradeable(BUSD).balanceOf(address(this)));
	}
	
	function getPairBalance() public view  returns (uint256, uint256) {
		return (pistonToken.balanceOf(address(uniswapV2Pair)), IERC20Upgradeable(BUSD).balanceOf(address(uniswapV2Pair)));
	}
	
	function getTokenAndControllerAddress() public view  returns (address, address) {
		return (address(pistonToken), address(this) );
	}
	
}

interface IToken {

	//variable readers
	function tokensInTrap() external returns(uint256);
	function trapWallet() external returns(address);

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