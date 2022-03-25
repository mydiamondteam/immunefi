# Piston Deploy Instructions

## Token:

### Setup after deploy: 
    setUniswapV2PairAndController with Controller Address and LP Address from Controller.
	
## Controller:
### Setup before Deploy:
    Insert Tokenaddress in Deploy Script (initializer)!
	
## PriceFeed:

### Setup after deploy: 
    setMarketPair with LP from Controller.
	
## PistonRace:
	
### Setup before deploy: 
    Change Piston Token address and PriceFeed address in code!
	
### After deployment: 
    Set Race Address and Ecoystem Wallet in Controller.
    Start the Race with deposit() by owner wallet.
    exclude he PistonRace contract from token taxes.
	
