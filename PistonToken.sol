// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract PistonToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {
	using SafeMathUpgradeable for uint256;
	
	bool public swapEnabled;
	bool public tradingEnabled;
	
	address public constant deadWallet = 0x000000000000000000000000000000000000dEaD; 
	
	uint256 public maxBuyAmount;
	uint256 public maxWalletBalance;
	uint256 public maxSellAmount;
	uint256 public swapTokensAtAmount;
	
	mapping(address => bool) public _isBlacklisted;
	
	uint256 public totalFees;		
	uint256 public extraSellFee;
	address public  uniswapV2Pair; // the main pair (PISTON/BUSD)
	address public  controller;
	address public mintMaster;
	
	// exlcude from fees and max transaction amount
	mapping (address => bool) private _isExcludedFromFees;
	// store addresses that a automatic market maker pairs. Any transfer *to* these addresses
	// could be subject to a maximum transfer amount
	mapping (address => bool) public automatedMarketMakerPairs;
	
	event ExcludeFromFees(address indexed account, bool isExcluded);
	event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

	
	function initialize() public virtual initializer {
		// base
		//
		__Ownable_init();
		__ERC20_init("PISTON", "PSTN");
		mintMaster = owner(); // initial owner = mintmaster (set to piston race contract later)    
		// exclude from paying fees or having max transaction amount
		excludeFromFees(owner(), true);
		excludeFromFees(address(this), true);
		mintMaster = owner(); // initial owner = mintmaster
		
		// settings
		swapEnabled = false;
		tradingEnabled = false;
		swapEnabled = true;
		tradingEnabled = true;
		maxBuyAmount = 20000 * (10**18);
		maxWalletBalance = 20000 * (10**18);
		maxSellAmount = 3000 * (10**18);
		
		swapTokensAtAmount = 250 * (10**18);
		
		
		
		totalFees = 10;
		extraSellFee = 0;
		_mint(owner(), 1000000 * (10**18));
	}
	
	function mint(address _to, uint256 _amount) external {
		require(msg.sender == mintMaster); // only allowed for mint master ( == piston race)
		_mint(_to, _amount);
	}
	
	receive() external payable {
	}    
	
	function excludeFromFees(address account, bool excluded) public onlyOwner {
		require(_isExcludedFromFees[account] != excluded, "PISTON: Account is already the value of 'excluded'");
		_isExcludedFromFees[account] = excluded;
		emit ExcludeFromFees(account, excluded);
	}
	
	function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
		for(uint256 i = 0; i < accounts.length; i++) {
			_isExcludedFromFees[accounts[i]] = excluded;
		}
		emit ExcludeMultipleAccountsFromFees(accounts, excluded);
	}
	
	function setUniswapV2PairAndController(address _uniswapV2Pair, address   _controller) external onlyOwner{
		uniswapV2Pair=address(_uniswapV2Pair);
		setAutomatedMarketMakerPair(_uniswapV2Pair, true);

		controller=address(_controller);
		excludeFromFees(controller, true);
	}
	
	function setFees(uint256 _totalFees, uint256 _extraSellFee) external onlyOwner{
		require(totalFees <= 10);	// regular user fees
		require(extraSellFee <= 15);	// for automatedMarketMakerPairs			
		totalFees = _totalFees;
		extraSellFee = _extraSellFee;		
			
	}   
	
	function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
		//require(pair != uniswapV2Pair, "PISTON: The PanBUSDSwap pair cannot be removed from automatedMarketMakerPairs");
		_setAutomatedMarketMakerPair(pair, value);
	}
	
	
	function blacklistAddress(address account, bool value) external onlyOwner{
		_isBlacklisted[account] = value;
	}
	
	function setTradingEnabled(bool _enabled) external onlyOwner{
		tradingEnabled = _enabled;
		swapEnabled = _enabled;
	}
	
	function _setAutomatedMarketMakerPair(address pair, bool value) private {
		//require(automatedMarketMakerPairs[pair] != value, "PISTON: Automated market maker pair is already set to that value");
		automatedMarketMakerPairs[pair] = value;
	}
	
	function setSwapEnabled(bool _enabled) external onlyOwner{
		swapEnabled = _enabled;
	}
	
	function setMaxBuyAmount(uint256 amount) external onlyOwner{
		maxBuyAmount = amount * 10**18;
	}
	
	function setMaxWalletBalance(uint256 amount) external onlyOwner{
		maxWalletBalance = amount * 10**18;
	}
	
	function setMaxSellAmount(uint256 amount) external onlyOwner{
		maxSellAmount = amount * 10**18;
	}
	
	function setSwapTokensAtAmount(uint256 amount) external onlyOwner{
		swapTokensAtAmount = amount * 10**18;
	}
	
	function isExcludedFromFees(address account) public view returns(bool) {
		return _isExcludedFromFees[account];
	}
	
	function setMintMasterAddress(address _value) external {
		require(msg.sender == mintMaster, "only the current mint master is allowed to do this");
		mintMaster = _value;
	}
	
	function _transfer(
	address from,
	address to,
	uint256 amount
	) internal override  {
		require(from != address(0), "ERC20: transfer from the zero address");
		require(to != address(0), "ERC20: transfer to the zero address");
		require(!_isBlacklisted[from] && !_isBlacklisted[to], 'Blacklisted address');
		
		if(!_isExcludedFromFees[from] && !_isExcludedFromFees[to]){
		require(tradingEnabled, "Trading not enabled");
		}
		
		if(amount == 0) {
			super._transfer(from, to, 0);
			return;
		}

		if(automatedMarketMakerPairs[from] && !_isExcludedFromFees[to]){
			require(amount <= maxBuyAmount, "You are exceeding maxBuyAmount");
		}
		if(!_isExcludedFromFees[from] && automatedMarketMakerPairs[to] ){
			require(amount <= maxSellAmount, "You are exceeding maxSellAmount");
		}
		if(!_isExcludedFromFees[from] && !automatedMarketMakerPairs[to] && !_isExcludedFromFees[to]){
			require(balanceOf(to).add(amount) <= maxWalletBalance, "Recipient is exceeding maxWalletBalance");
		}
		uint256 contractTokenBalance = balanceOf(address(this));
		bool canSwap = contractTokenBalance >= swapTokensAtAmount;
		if(
		canSwap &&
		!automatedMarketMakerPairs[from] &&
		swapEnabled &&
		from != owner() &&
		to != owner() &&
		from != controller &&
		to != controller
		
		) {
			contractTokenBalance = swapTokensAtAmount;
			
			// transfer contractTokenBalance to  controller     
			super._transfer(address(this), controller, contractTokenBalance);
		}
		bool takeFee = true;
		// if any account belongs to _isExcludedFromFee account then remove the fee
		if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
			takeFee = false;
		}
		if(takeFee) {
			uint256 fees = amount.mul(totalFees).div(100);
			if(automatedMarketMakerPairs[to]){
				fees += amount.mul(extraSellFee).div(100);
			}
			amount = amount.sub(fees);
			super._transfer(from, address(this), fees);
		}
		super._transfer(from, to, amount);	
		
	}  
}
