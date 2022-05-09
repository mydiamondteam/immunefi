// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Race is OwnableUpgradeable {

    using SafeMath for uint256;

    struct User {
        //Referral Info
        address upline;
        uint256 referrals;
        uint256 total_structure;

        //Long-term Referral Accounting
        uint256 direct_bonus;
        uint256 match_bonus;

        //Deposit Accounting
        uint256 deposits;
        uint256 deposit_time;

        //Payout and Roll Accounting
        uint256 payouts;
        uint256 rolls;

        //Upline Round Robin tracking
        uint256 ref_claim_pos;

        uint256 accumulatedDiv;

        //Record Deposits of users for eject function
        UserDepositsForEject[] userDepositsForEject;
    }

    struct UserDepositsForEject {
		uint256 amount_PSTN;
        uint256 amount_BUSD; // real amount in BUSD
		uint256 depositTime;
        bool ejected;
	}

    struct UserDepositReal {
        uint256 deposits; // real amount of Tokens
        uint256 deposits_BUSD; // real amount in BUSD
    }

    struct Airdrop {
        //Airdrop tracking
        uint256 airdrops;
        uint256 airdrops_received;
        uint256 last_airdrop;
    }

    struct UserBoost {
        //StakedBoost tracking
        address user;
        uint256 stakedBoost_PSTN;
        uint256 stakedBoost_BUSD;
        uint256 last_action_time;
    }    

    struct UserWithdrawn {
        uint256 withdrawn; // amount of Tokens
        uint256 withdrawn_BUSD; // amount in BUSD
    }

    ITokenMint private tokenMint;
    IToken private pistonToken;
    ITokenPriceFeed private pistonTokenPriceFeed;
    
    mapping(address => User) public users;
    mapping(address => UserDepositReal) public usersRealDeposits;
    mapping(address => Airdrop) public airdrops;
    
    mapping(uint256 => address) public id2Address;
    mapping(address => UserBoost) public usersBoosts;

    uint256 public CompoundTax;
    uint256 public ExitTax;
    uint256 public EjectTax;
    uint256 public DepositTax;

    uint256 private payoutRate;
    uint256 private ref_depth;
    uint256 private ref_bonus;
    uint256 private max_deposit_multiplier;
	uint256 private userDepositEjectDays;

    uint256 private minimumInitial;
    uint256 private minimumAmount;

    uint256 public deposit_bracket_size;     // @BB 5% increase whale tax per 5000 tokens... 10 below cuts it at 50% since 5 * 10
    uint256 public max_payout_cap;           // 50K PISTON or 10% of supply
    uint256 private deposit_bracket_max;     // sustainability fee is (bracket * 5)
    uint256 public min_staked_boost_amount;  // Minimum staked Boost amount should be the same as 0 level ref_depth amount.

    uint256[] public ref_balances;

    uint256 public total_airdrops;
    uint256 public total_users;
    uint256 public total_deposited;
    uint256 public total_withdraw;
    uint256 public total_bnb;
    uint256 public total_txs;

    bool public STORE_BUSD_VALUE;
    uint256 public AIRDROP_MIN_AMOUNT;

    mapping(address => UserWithdrawn) public usersWithdrawn;
    bool public AIRDROP_ENABLED;
    bool public EJECT_ENABLED;

    event Upline(address indexed addr, address indexed upline);
    event NewDeposit(address indexed addr, uint256 amount);
    event Leaderboard(address indexed addr, uint256 referrals, uint256 total_deposits, uint256 total_payouts, uint256 total_structure);
    event DirectPayout(address indexed addr, address indexed from, uint256 amount);
    event MatchPayout(address indexed addr, address indexed from, uint256 amount);
    event BalanceTransfer(address indexed _src, address indexed _dest, uint256 _deposits, uint256 _payouts);
    event Withdraw(address indexed addr, uint256 amount);
    event LimitReached(address indexed addr, uint256 amount);
    event NewAirdrop(address indexed from, address indexed to, uint256 amount, uint256 timestamp);
    event ManagerUpdate(address indexed addr, address indexed manager, uint256 timestamp);
    event BeneficiaryUpdate(address indexed addr, address indexed beneficiary);
    event HeartBeatIntervalUpdate(address indexed addr, uint256 interval);
    event HeartBeat(address indexed addr, uint256 timestamp);
    event Ejected(address indexed addr, uint256 amount, uint256 timestamp);

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();

        total_users = 1;
        deposit_bracket_size = 5000 ether;     // @BB 5% increase whale tax per 5000 tokens... 
        max_payout_cap = 50000 ether;          // 50k PISTON or 5% of supply

        //should remain 1e18 so we can set minimum to below 1 depending on the future price of piston.
        minimumInitial = 1 * 1e18;
        minimumAmount = 1 * 1e18;
        min_staked_boost_amount = 2 ether;
        AIRDROP_MIN_AMOUNT = 1 * 1e18;

        userDepositEjectDays = 7 days;
        payoutRate = 1;
        ref_depth  = 15;
        ref_bonus  = 5; // 5 % to round robin
        max_deposit_multiplier = 5;
        deposit_bracket_max = 10;  // sustainability fee is (bracket * 5)

        CompoundTax = 3;
        ExitTax = 10;
        EjectTax = 10;
        DepositTax = 10;

        AIRDROP_ENABLED = true;

        STORE_BUSD_VALUE = false; // this will be true after the priceFeedContract was set by updatePistonTokenPriceFeed(...)
        pistonToken = IToken(address(0xBfACD29427fF376FF3BC22dfFB29866277cA5Fb4)); // PISTON Token MAINNET
        tokenMint = ITokenMint(address(0xBfACD29427fF376FF3BC22dfFB29866277cA5Fb4)); // PISTON Token MAINNET

        updatePistonTokenPriceFeed(address(0x83Fe5acD13CdC965CFFCdCaC35686Dd69796897C), true);

        //Pit Crew Boost levels
        ref_balances.push(100 ether);           // 1 $100 worth of PSTN   
        ref_balances.push(300 ether);           // 2 $300 worth of PSTN
        ref_balances.push(500 ether);           // 3 $500 worth of PSTN
        ref_balances.push(700 ether);           // 4 $700 worth of PSTN
        ref_balances.push(900 ether);           // 5 $900 worth of PSTN
        ref_balances.push(1100 ether);          // 6 $1100 worth of PSTN
        ref_balances.push(1300 ether);          // 7 $1300 worth of PSTN
        ref_balances.push(1500 ether);          // 8 $1500 worth of PSTN
        ref_balances.push(1700 ether);          // 9 $1700 worth of PSTN
        ref_balances.push(1900 ether);          // 10 $1900 worth of PSTN
        ref_balances.push(2100 ether);          // 11 $2100 worth of PSTN
        ref_balances.push(2300 ether);          // 12 $2300 worth of PSTN
        ref_balances.push(2500 ether);          // 13 $2500 worth of PSTN
        ref_balances.push(2700 ether);          // 14 $2700 worth of PSTN
        ref_balances.push(2900 ether);          // 15 $2900 worth of PSTN
    }
        

    /****** Administrative Functions ******/
    function updateTaxes(uint256 _depositTax, uint256 _exitTax, uint256 _compoundTax) external onlyOwner {
        DepositTax = _depositTax;
        ExitTax = _exitTax;
        CompoundTax = _compoundTax;
    }
    
    function updatePistonTokenPriceFeed(address priceFeedAddress, bool _store_busd_enabled) public onlyOwner {
        pistonTokenPriceFeed = ITokenPriceFeed(priceFeedAddress);
        STORE_BUSD_VALUE = _store_busd_enabled;
    }

    function updatePayoutRate(uint256 _newPayoutRate) external onlyOwner {
        payoutRate = _newPayoutRate;
    }

    function updateRefDepth(uint256 _newRefDepth) external onlyOwner {
        ref_depth = _newRefDepth;
    }

    function updateRefBonus(uint256 _newRefBonus) external onlyOwner {
        ref_bonus = _newRefBonus;
    }

    function updateInitialDeposit(uint256 _newInitialDeposit) external onlyOwner {
        minimumInitial = _newInitialDeposit * 1e18;
    }

    function updateMinimumAmount(uint256 _newminimumAmount) external onlyOwner {
        minimumAmount = _newminimumAmount * 1e18;
    }


    function updateDepositBracketSize(uint256 _newBracketSize) external onlyOwner {
        deposit_bracket_size = _newBracketSize * 1 ether;
    }

    function updateMaxPayoutCap(uint256 _newPayoutCap) external onlyOwner {
        max_payout_cap = _newPayoutCap * 1 ether;
    }

    function updateMinimumStakedBoostAmount(uint256 _newMinimumStakedBoostAmount) external onlyOwner {
        min_staked_boost_amount = _newMinimumStakedBoostAmount;
    }

    function updateMinimumAirdropAmount(uint256 value) public onlyOwner {
        AIRDROP_MIN_AMOUNT = value;
    }

    function updateAirdropEnabled(bool value) external onlyOwner {
        AIRDROP_ENABLED = value;
    }
    function updateEjectEnabled(bool value) external onlyOwner {
        EJECT_ENABLED = value;
    }
															  
											  
	 

    function updateHoldRequirements(uint256[] memory _newRefBalances) external onlyOwner {
        require(_newRefBalances.length == ref_depth);
        delete ref_balances;
        for(uint8 i = 0; i < ref_depth; i++) {
            ref_balances.push(_newRefBalances[i]);
        }
    }

    /****** User Fuctions ******/
    //deposit_amount -- can only be done by the project address for first deposit.
    function deposit(uint256 _amount) external onlyOwner{
        _deposit(msg.sender, _amount);
    }

    //@dev Deposit specified PISTON amount supplying an upline referral
    function deposit(address _upline, uint256 _amount) external {

        address _addr = msg.sender;

        require(!HasUsedEject(_addr), "user is ejected");

        (uint256 realizedDeposit,) = calculateDepositTax(_amount);
        uint256 _total_amount = realizedDeposit;
        uint256 _total_amount_real = realizedDeposit;

        require(_amount >= minimumAmount, "Minimum deposit");

        //If fresh account require a minimal amount of PISTON
        if (users[_addr].deposits == 0){
            require(_amount >= minimumInitial, "Initial deposit too low");
        }

        _setUpline(_addr, _upline);

        uint256 taxedDivs;
        // roll if divs are greater than 1% of the deposit
        if (claimsAvailable(_addr) > _amount / 100 
            && users[_addr].deposits < this.maxRollOf(usersRealDeposits[_addr].deposits) // don't roll if user has reached 5x
            ){
            uint256 claimedDivs = _claim(_addr, true);
             taxedDivs = claimedDivs.sub(claimedDivs.mul(CompoundTax).div(100)); // 3% tax on compounding
            _total_amount += rollAmountOf(_addr, taxedDivs, true); // reduce the rollable amount if the user will reach the 5x limit with this roll
            taxedDivs = taxedDivs / 2;
        }

        //Transfer PISTON Tokens to the contract
        require(
            pistonToken.transferFrom(
                _addr,
                address(this),
                _amount
            ),
            "PISTON token transfer failed"
        );

        // record user new deposit (here comes fresh money. userRealDeposits only contains the amount from external. nothing from roll)
        usersRealDeposits[_addr].deposits += _total_amount_real;
        if(STORE_BUSD_VALUE){
            usersRealDeposits[_addr].deposits_BUSD += pistonTokenPriceFeed.getPrice(1).mul(_total_amount_real).div(1 ether); // new cash in BUSD
        }

        //per user deposit, 10% goes to sustainability tax. 

        _deposit(_addr, _total_amount);

        _refPayout(_addr, realizedDeposit + taxedDivs, ref_bonus);

        /** deposit amount and Time of Deposits/ it will record all new deposits of the user. 
            This mapping will be used to check if the deposits is will qualified for eject **/
		users[_addr].userDepositsForEject.push(
            UserDepositsForEject(
                _total_amount_real, 
                pistonTokenPriceFeed.getPrice(1).mul(_total_amount_real).div(1 ether), 
                block.timestamp,
                false
            )
        );

        emit Leaderboard(_addr, users[_addr].referrals, users[_addr].deposits, users[_addr].payouts, users[_addr].total_structure);
        total_txs++;

    }
    
    function stakeBoostSimulate(address _addr, uint256 _amount) external view returns (uint256 stakedPSTN, uint256 stakedBUSD) {

        require(users[_addr].upline != address(0) || _addr == owner(), "user not found"); // non existent user has no upline
        require(STORE_BUSD_VALUE, "BUSD storing is disabled");
        require(!HasUsedEject(msg.sender), "user used eject");
        require(_amount >= min_staked_boost_amount,"Did not meet minimum amount that can be staked.");
        
        stakedPSTN = usersBoosts[_addr].stakedBoost_PSTN + _amount;

        if(STORE_BUSD_VALUE){
            uint256 pistonPrice = pistonTokenPriceFeed.getPrice(1);            
            stakedBUSD = usersBoosts[_addr].stakedBoost_BUSD + pistonPrice.mul(_amount).div(1 ether);
        }
    }

    //record to usersBoosts users staked pstn token and its dollar value.
    function stakeBoost(uint256 _amount) external {

        address _addr = msg.sender;
        require(users[_addr].upline != address(0) || _addr == owner(), "user not found"); // non existent user has no upline
        require(STORE_BUSD_VALUE, "BUSD storing is disabled");
        require(!HasUsedEject(msg.sender), "user used eject");
        require(_amount >= min_staked_boost_amount,"Did not meet minimum amount that can be staked.");
        require(
            pistonToken.transferFrom(
                _addr,
                address(this),
                _amount
            ),
            "PISTON to contract transfer failed; check balance and allowance for staking."
        );
        
        usersBoosts[_addr].stakedBoost_PSTN += _amount;
        usersBoosts[_addr].last_action_time = block.timestamp;
        if(STORE_BUSD_VALUE){
            uint256 pistonPrice = pistonTokenPriceFeed.getPrice(1);            
            usersBoosts[_addr].stakedBoost_BUSD += pistonPrice.mul(_amount).div(1 ether);
        }
    }

    function unstakeBoost() external {
        address _addr = msg.sender;
        (,uint256 _max_payout ,,) = payoutOf(_addr);
        
        require(users[_addr].payouts >= _max_payout || HasUsedEject(_addr) || users[_addr].referrals == 0, "User can only unstakeBoost if max payout has been reached or the race is over.");
        require(usersBoosts[_addr].stakedBoost_PSTN > 0,"nothing staked");
        uint256 pistonPrice = pistonTokenPriceFeed.getPrice(1);

        require(pistonPrice > 0, "piston price missing");

        //allow to unstakeBoost the dollar amount of the staked pstn tokens.
        //same rules as in eject here. if price has increased, the dollar amount is the cap. if the price has fallen the pston amount is the cap.

        uint256 amountAvailableForUnstakeBoost = 0;
        uint256 current_amount_BUSD = pistonPrice.mul(usersBoosts[_addr].stakedBoost_PSTN).div(1 ether);

        //check if current busd price of users deposited pstn token is greater that pstn amount(in busd) deposited.
        if(current_amount_BUSD >= usersBoosts[_addr].stakedBoost_BUSD){
            amountAvailableForUnstakeBoost += SafeMath.min(usersBoosts[_addr].stakedBoost_BUSD.mul(1 ether).div(pistonPrice), usersBoosts[_addr].stakedBoost_PSTN);                
        }
        //else-if the current busd price of users deposited pstn token is lower than pstn amount(in busd) deposited.
        else if(current_amount_BUSD <= usersBoosts[_addr].stakedBoost_BUSD){
            amountAvailableForUnstakeBoost += usersBoosts[_addr].stakedBoost_PSTN;
        }     

        //set user stakeBoost Token to 0
        usersBoosts[_addr].stakedBoost_PSTN = 0;
        usersBoosts[_addr].stakedBoost_BUSD = 0;
        usersBoosts[_addr].last_action_time = block.timestamp;

        //mint new tokens if reward vault is getting low, or amountAvailableForUnstakeBoost is higher than the tokens inside the contract.
        uint256 vaultBalance = getVaultBalance();
        if(vaultBalance < amountAvailableForUnstakeBoost) {
            uint256 differenceToMint = amountAvailableForUnstakeBoost.sub(vaultBalance);
            tokenMint.mint(address(this), differenceToMint);
        }

        //transfer amount to the user
        require(
            pistonToken.transfer(
                address(_addr),
                amountAvailableForUnstakeBoost
            ),
            "PISTON from contract transfer failed; check balance and allowance for unstaking."
        );
    }

    function unstakeBoostSimulate(address _addr) external view returns (uint256) {

        (,uint256 _max_payout ,,) = payoutOf(_addr);
        
        require(users[_addr].payouts >= _max_payout || HasUsedEject(_addr) || users[_addr].referrals == 0, "User can only unstakeBoost if max payout has been reached or the race is over.");
        require(usersBoosts[_addr].stakedBoost_PSTN > 0, "nothing staked");
        uint256 pistonPrice = pistonTokenPriceFeed.getPrice(1);

        require(pistonPrice > 0, "piston price missing");

        //allow to unstakeBoost the dollar amount of the staked pstn tokens.
        //same rules as in eject here. if price has increased, the dollar amount is the cap. if the price has fallen the pston amount is the cap.

        uint256 amountAvailableForUnstakeBoost = 0;
        uint256 current_amount_BUSD = pistonPrice.mul(usersBoosts[_addr].stakedBoost_PSTN).div(1 ether);

        //check if current busd price of users deposited pstn token is greater that pstn amount(in busd) deposited.
        if(current_amount_BUSD >= usersBoosts[_addr].stakedBoost_BUSD){
            amountAvailableForUnstakeBoost += SafeMath.min(usersBoosts[_addr].stakedBoost_BUSD.mul(1 ether).div(pistonPrice), usersBoosts[_addr].stakedBoost_PSTN);                
        }
        //else-if the current busd price of users deposited pstn token is lower than pstn amount(in busd) deposited.
        else if(current_amount_BUSD <= usersBoosts[_addr].stakedBoost_BUSD){
            amountAvailableForUnstakeBoost += usersBoosts[_addr].stakedBoost_PSTN;
        }     

        return amountAvailableForUnstakeBoost;
    }

    //@dev Claim, transfer, withdraw from vault
    function claim() external {

        address _addr = msg.sender;

        _claim_out(_addr);
    }

    //@dev Claim and deposit;
    function roll() external {

        address _addr = msg.sender;

        _roll(_addr);
    }

    /******************** Internal Fuctions ********************/

    //@dev Add direct referral and update team structure of upline
    function _setUpline(address _addr, address _upline) internal {
        /*
        1) User must not have existing up-line
        2) sender cannot use his address as up-line.
        3) sender address should not be equal to the contract owner address.
        4) up-line(referrer address) must have an existing deposit in to the protocol
        */
        if(users[_addr].upline == address(0) && !HasUsedEject(_upline) && _upline != _addr && _addr != owner() && (users[_upline].deposit_time > 0 || _upline == owner() )) {
            users[_addr].upline = _upline;
            users[_upline].referrals++;

            emit Upline(_addr, _upline);

            if(users[_addr].deposits == 0 ){ // new user
                id2Address[total_users] = _addr;
            }
            total_users++;

            for(uint8 i = 0; i < ref_depth; i++) {
                if(_upline == address(0)) break;

                users[_upline].total_structure++;

                _upline = users[_upline].upline;
            }
        }
    }

    //@dev Deposit
    function _deposit(address _addr, uint256 _amount) internal {
        //Can't maintain upline referrals without this being set
        require(users[_addr].upline != address(0) || _addr == owner(), "No upline");

        //update user statistics
        users[_addr].deposits += _amount; // add amount to deposits
        users[_addr].deposit_time = block.timestamp;
        total_deposited += _amount;

        //events
        emit NewDeposit(_addr, _amount);
    }

    //Payout upline; Bonuses are from 5 - 30% on the 1% paid out daily; Referrals only help
    function _refPayout(address _addr, uint256 _amount, uint256 _refBonus) internal {
        //for deposit _addr is the sender/depositor

        address _up = users[_addr].upline;
        uint256 _bonus = _amount * _refBonus / 100; // 5% of amount

        for(uint8 i = 0; i < ref_depth; i++) {

            // If we have reached the top of the chain, the owner
            if(_up == address(0)){
                //The equivalent of looping through all available
                users[_addr].ref_claim_pos = ref_depth;
                break;
            }

            //We only match if the claim position is valid
            //user can only get refpayout if user has not reach x5 max deposit
            if(users[_addr].ref_claim_pos == i) {
                if (isBalanceCovered(_up, i + 1) && isNetPositive(_up) && !HasUsedEject(_up) &&
                users[_up].deposits.add(_bonus) < this.maxRollOf(usersRealDeposits[_up].deposits)){

                    (uint256 gross_payout,,,) = payoutOf(_up);
                    users[_up].accumulatedDiv = gross_payout;
                    users[_up].deposits += _bonus;
                    users[_up].deposit_time = block.timestamp;


                    //match accounting
                    users[_up].match_bonus += _bonus;

                    //events
                    emit NewDeposit(_up, _bonus);
                    emit MatchPayout(_up, _addr, _bonus);
                    

                    if (users[_up].upline == address(0)){
                        users[_addr].ref_claim_pos = ref_depth;
                    }

                    //conditions done, break statement
                    break;
                }

                users[_addr].ref_claim_pos += 1;

            }

            _up = users[_up].upline;

        }

        //Reward next position for referrals
        users[_addr].ref_claim_pos += 1;

        //Reset if ref_depth or all positions are rewarded.
        if (users[_addr].ref_claim_pos >= ref_depth){
            users[_addr].ref_claim_pos = 0;
        }
    }

    // calculates the next ref address
    function getNextUpline(address _addr, uint256 _amount, uint256 _refBonus) public view returns (address _next_upline, bool _balance_coverd, bool _net_positive, bool _max_roll_ok ) {

        address _up = users[_addr].upline;
        uint256 _bonus = _amount * _refBonus / 100;

        for(uint8 i = 0; i < ref_depth; i++) {
            // If we have reached the top of the chain, the owner
            if(_up == address(0)){
                break;
            }

            //We only match if the claim position is valid
            if(users[_addr].ref_claim_pos == i) {
                _balance_coverd = isBalanceCovered(_up, (i + 1));
                _net_positive = isNetPositive(_up);
                _max_roll_ok = users[_addr].deposits.add(_bonus) < this.maxRollOf(usersRealDeposits[_addr].deposits);
                
                return (_up, _balance_coverd, _net_positive, _max_roll_ok);
            }

            _up = users[_up].upline;
        }        

        return (address(0), false, false, false);
    }

    //@dev Claim and deposit;
    function _roll(address _addr) internal {

        require(!HasUsedEject(msg.sender), "user used eject");

        uint256 to_payout = _claim(_addr, false);

        uint256 payout_taxed = to_payout.mul(SafeMath.sub(100, CompoundTax)).div(100); // 3% tax on compounding
        
        uint256 roll_amount_final = rollAmountOf(_addr, payout_taxed);

        _deposit(_addr, roll_amount_final);

        //track rolls for net positive
        users[_addr].rolls += roll_amount_final;

        emit Leaderboard(_addr, users[_addr].referrals, users[_addr].deposits, users[_addr].payouts, users[_addr].total_structure);
        total_txs++;

    }

    function rollAmountOf(address _addr, uint256 _toBeRolledAmount) view public returns(uint256 rollAmount) {
        return rollAmountOf(_addr, _toBeRolledAmount, /*default*/false);
    }

    //get the amount that can be rolled
    function rollAmountOf(address _addr, uint256 _toBeRolledAmount, bool _avoid_revert) view public returns(uint256 rollAmount) {
        
        //validate the total amount that can be rolled is 5x the users real deposit only.
        uint256 maxRollAmount = maxRollOf(usersRealDeposits[_addr].deposits); 

        rollAmount = _toBeRolledAmount; 

        if(_avoid_revert == false){
            if(users[_addr].deposits >= maxRollAmount) { // user already got max roll
                revert("User exceeded x5 of total deposit to be rolled.");
            }
        }else{
            if(users[_addr].deposits >= maxRollAmount) { // user already got max roll
                rollAmount = 0;
                return rollAmount;
            }
        }

        if(users[_addr].deposits.add(rollAmount) >= maxRollAmount) { // user will reach max roll with current roll
            rollAmount = maxRollAmount.sub(users[_addr].deposits); // only let him roll until max roll is reached
        }        
    }

    //max roll per user is 5x user deposit.
    function maxRollOf(uint256 _amount) view public returns(uint256) {
        return _amount.mul(max_deposit_multiplier);
    }


    //@dev Claim, transfer, and topoff
    function _claim_out(address _addr) internal {

        uint256 to_payout = _claim(_addr, true);
        uint256 realizedPayout = to_payout.mul(SafeMath.sub(100, ExitTax)).div(100); // 10% tax on withdraw
        
        //mint new tokens if reward vault is getting low, or realizedPayout is higher than the tokens inside the contract.
        uint256 vaultBalance = getVaultBalance();
        if(vaultBalance < realizedPayout) {
            uint256 differenceToMint = realizedPayout.sub(vaultBalance);
            tokenMint.mint(address(this), differenceToMint);
        }
	
	//update user withdrawn statistics.
        usersWithdrawn[_addr].withdrawn += realizedPayout;
        usersWithdrawn[_addr].withdrawn_BUSD += pistonTokenPriceFeed.getPrice(1).mul(realizedPayout).div(1 ether);

        //transfer payout to the investor address
        require(pistonToken.transfer(address(msg.sender), realizedPayout));

        emit Leaderboard(_addr, users[_addr].referrals, users[_addr].deposits, users[_addr].payouts, users[_addr].total_structure);
        total_txs++;

    }

    //@dev Claim current payouts
    function _claim(address _addr, bool isClaimedOut) internal returns (uint256) {
        (uint256 _gross_payout, uint256 _max_payout, uint256 _to_payout,) = payoutOf(_addr);
        require(users[_addr].payouts < _max_payout, "Full payouts");
        require(!HasUsedEject(_addr), "user is ejected");

        // Deposit payout
        if(_to_payout > 0) {

            // payout remaining allowable divs if exceeds
            if(users[_addr].payouts + _to_payout > _max_payout) {
                _to_payout = _max_payout.safeSub(users[_addr].payouts);
            }

            users[_addr].payouts += _gross_payout;


            if (!isClaimedOut){
                //Payout referrals
                uint256 compoundTaxedPayout = _to_payout.mul(SafeMath.sub(100, CompoundTax)).div(100); // 3% tax on compounding
                _refPayout(_addr, compoundTaxedPayout, CompoundTax);
            }
        }

        require(_to_payout > 0, "Zero payout");

        //Update global statistics
        total_withdraw += _to_payout;

        //Update user statistics
        users[_addr].deposit_time = block.timestamp;
        users[_addr].accumulatedDiv = 0;

        emit Withdraw(_addr, _to_payout);

        if(users[_addr].payouts >= _max_payout) {
            emit LimitReached(_addr, users[_addr].payouts);
        }

        return _to_payout;
    }

    function calculateDepositTax(uint256 _value) public view returns (uint256 adjustedValue, uint256 taxAmount){
        taxAmount = _value.mul(DepositTax).div(100);

        adjustedValue = _value.sub(taxAmount);
        return (adjustedValue, taxAmount);
    }

    function eject() external {
        require(EJECT_ENABLED, "eject is not enabled");

        User storage user = users[msg.sender]; // user statistics
        uint256 amountAvailableForEject;
        uint256 amountDeposits_PSTN;
        uint256 pistonPrice = pistonTokenPriceFeed.getPrice(1);

        require(!HasUsedEject(msg.sender), "user already used eject");
        require(pistonPrice > 0, "piston price missing");
        require(user.userDepositsForEject.length > 0, "no deposits");
        require(user.userDepositsForEject[0].depositTime > block.timestamp.sub(userDepositEjectDays), "eject period is over"); // use first deposit time for begin of the period

        for (uint256 i = 0; i < user.userDepositsForEject.length; i++) {
            if(user.userDepositsForEject[i].ejected == false){
                amountDeposits_PSTN += user.userDepositsForEject[i].amount_PSTN;
                user.userDepositsForEject[i].ejected = true;
            }
		}

		amountAvailableForEject = amountDeposits_PSTN; 																								

        //update user deposit info 
        user.deposits = 0; // eject == game over
        user.payouts = 0;
        user.accumulatedDiv = 0;
        usersRealDeposits[msg.sender].deposits = 0;
        airdrops[msg.sender].airdrops = 0;
        user.rolls = 0;

        if(STORE_BUSD_VALUE){
            usersRealDeposits[msg.sender].deposits_BUSD = 0;
        }

        //transfer payout to the investor address less 10% sustainability fee
        uint256 ejectTaxAmount = amountAvailableForEject.mul(EjectTax).div(100);
        amountAvailableForEject = amountAvailableForEject.safeSub(ejectTaxAmount);

        require(usersWithdrawn[msg.sender].withdrawn < amountAvailableForEject, "withdrawn amount is higher than eject amount");

        //emit EjectDebug(msg.sender, amountAvailableForEject, usersWithdrawn[msg.sender].withdrawn, block.timestamp);
        amountAvailableForEject = amountAvailableForEject.safeSub(usersWithdrawn[msg.sender].withdrawn);

        //mint new tokens if reward vault is getting low, or amountAvailableForEject is higher than the tokens inside the contract.
        uint256 vaultBalance = getVaultBalance();
        if(vaultBalance < amountAvailableForEject) {
            uint256 differenceToMint = amountAvailableForEject.sub(vaultBalance);
            tokenMint.mint(address(this), differenceToMint);
        }

        require(pistonToken.transfer(address(msg.sender), amountAvailableForEject));

        emit Ejected(msg.sender, amountAvailableForEject, block.timestamp);
    }

    function ejectSimulate(address _addr) external view returns (uint256) {

        User storage user = users[_addr]; // user statistics
        uint256 amountAvailableForEject;
        uint256 amountDeposits_PSTN;
        uint256 pistonPrice = pistonTokenPriceFeed.getPrice(1);

        require(!HasUsedEject(_addr), "user already used eject");
        require(pistonPrice > 0, "piston price missing");
        require(user.userDepositsForEject.length > 0, "no deposits");
        require(user.userDepositsForEject[0].depositTime > block.timestamp.sub(userDepositEjectDays), "eject period is over"); // use first deposit time for begin of the period

        for (uint256 i = 0; i < user.userDepositsForEject.length; i++) {
            if(user.userDepositsForEject[i].ejected == false){
                amountDeposits_PSTN += user.userDepositsForEject[i].amount_PSTN;
            }
		}

		amountAvailableForEject = amountDeposits_PSTN; 																								

        //transfer payout to the investor address less 10% sustainability fee
        uint256 ejectTaxAmount = amountAvailableForEject.mul(EjectTax).div(100);
        amountAvailableForEject = amountAvailableForEject.safeSub(ejectTaxAmount);

        require(usersWithdrawn[_addr].withdrawn < amountAvailableForEject, "withdrawn amount is higher than eject amount");

        //emit EjectDebug(msg.sender, amountAvailableForEject, usersWithdrawn[msg.sender].withdrawn, block.timestamp);
        amountAvailableForEject = amountAvailableForEject.safeSub(usersWithdrawn[_addr].withdrawn);


        return amountAvailableForEject;
    }


    /*************************** Views ***************************/

    //@dev Returns true if the address is net positive
    function isNetPositive(address _addr) public view returns (bool) {

        if(HasUsedEject(_addr)){
            return false;
        }

        (uint256 _credits, uint256 _debits) = creditsAndDebits(_addr);

        return _credits > _debits;

    }

    //@dev Returns the total credits and debits for a given address
    function creditsAndDebits(address _addr) public view returns (uint256 _credits, uint256 _debits) {
        User memory _user = users[_addr];
        Airdrop memory _airdrop = airdrops[_addr];

        _credits = _airdrop.airdrops + _user.rolls + _user.deposits;
        _debits = _user.payouts;

    }

    function HasUsedEject(address _addr) public view returns (bool) {
        User memory _user = users[_addr];
        if(_user.userDepositsForEject.length > 0){
            return _user.userDepositsForEject[0].ejected;
        }
        return false;
    }

    //@dev Returns whether PSTN balance matches level
    function isBalanceCovered(address _addr, uint8 _level) public view returns (bool) {
        if (users[_addr].upline == address(0)){
            return true;
        }
        return balanceLevel(_addr) >= _level;
    }

    //@dev Returns the level of the address
    function balanceLevelOld(address _addr) public view returns (uint8) {
        uint8 _level = 0;
        for (uint8 i = 0; i < ref_depth; i++) {
            //check if users staked boost(in BUSD) is less then ref_balances ( ether value/ busd value)
            if (usersBoosts[_addr].stakedBoost_BUSD < ref_balances[i]) break;
            _level += 1;
        }

        return _level;
    }

    function balanceLevel(address _addr) public view returns (uint8) {
        uint8 _level = 0;
        for (uint8 i = 0; i < ref_depth; i++) {
            //check if users staked boost(in BUSD) is less then ref_balances ( ether value/ busd value)
            if (usersBoosts[_addr].stakedBoost_BUSD.mul(101).div(100) < ref_balances[i]) break; // 1% tolerance because of piston/busd price impact
            _level += 1;
        }

        return _level;
    }

    //@dev Returns amount of claims available for sender
    function claimsAvailable(address _addr) public view returns (uint256) {
        (,,uint256 _to_payout,) = payoutOf(_addr);
        return _to_payout;
    }

    //@dev Maxpayout of 3.65x of deposit
    function maxPayoutOf(uint256 _amount) public pure returns(uint256) {
        return _amount * 365 / 100;
    }

    function sustainabilityFeeV2(address _addr, uint256 _pendingDiv) public view returns (uint256) {
        uint256 _bracket = users[_addr].payouts.add(_pendingDiv).div(deposit_bracket_size);
        _bracket = SafeMath.min(_bracket, deposit_bracket_max);
        return _bracket * 5;
    }

    //@dev Calculate the current payout and maxpayout of a given address
    function payoutOf(address _addr) public view returns(uint256 payout, uint256 max_payout, uint256 net_payout, uint256 sustainability_fee) {
        //The max_payout is capped so that we can also cap available rewards daily
        max_payout = maxPayoutOf(users[_addr].deposits).min(max_payout_cap);

        uint256 share;

        if(users[_addr].payouts < max_payout) {

            //Using 1e18 we capture all significant digits when calculating available divs
            share = users[_addr].deposits.mul(payoutRate * 1e18).div(100e18).div(24 hours); //divide the profit by payout rate and seconds in the day

            payout = share * block.timestamp.safeSub(users[_addr].deposit_time);

            payout += users[_addr].accumulatedDiv;

            // payout remaining allowable divs if exceeds
            if(users[_addr].payouts + payout > max_payout) {
                payout = max_payout.safeSub(users[_addr].payouts);
            }

            uint256 _fee = sustainabilityFeeV2(_addr, payout);

            sustainability_fee = payout * _fee / 100;

            net_payout = payout.safeSub(sustainability_fee);

        }
    }

    //@dev Get current user snapshot
    function userInfo(address _addr) external view returns(address upline, uint256 deposit_time, uint256 deposits, uint256 payouts, uint256 direct_bonus, uint256 match_bonus, uint256 last_airdrop) {
        return (users[_addr].upline, users[_addr].deposit_time, users[_addr].deposits, users[_addr].payouts, users[_addr].direct_bonus, users[_addr].match_bonus, airdrops[_addr].last_airdrop);
    }

    //@dev Get user totals
    function userInfoTotals(address _addr) external view returns(uint256 referrals, uint256 total_deposits, uint256 total_payouts, uint256 total_structure, uint256 airdrops_total, uint256 airdrops_received) {
        return (users[_addr].referrals, users[_addr].deposits, users[_addr].payouts, users[_addr].total_structure, airdrops[_addr].airdrops, airdrops[_addr].airdrops_received);
    }

    function userInfoRealDeposits(address _addr) external view returns(uint256 deposits_real, uint256 deposits_real_busd) {
        return (usersRealDeposits[_addr].deposits, usersRealDeposits[_addr].deposits_BUSD);
    }

    function userDepositsForEjectLength(address _addr) external view returns(uint256 length) {
        return (users[_addr].userDepositsForEject.length);
    }

    function userDepositsForEject(address _addr, uint256 index) external view returns(uint256 amount_PSTN, uint256 amount_BUSD, uint256 depositTime, bool ejected) {
        return (users[_addr].userDepositsForEject[index].amount_PSTN, users[_addr].userDepositsForEject[index].amount_BUSD, users[_addr].userDepositsForEject[index].depositTime, users[_addr].userDepositsForEject[index].ejected);
    }

    function getVaultBalance() public view returns (uint256) {
        return pistonToken.balanceOf(address(this));
	}

    //@dev Get contract snapshot
    function contractInfo() external view returns(uint256 _total_users, uint256 _total_deposited, uint256 _total_withdraw, uint256 _total_bnb, uint256 _total_txs, uint256 _total_airdrops, uint256 _tokenPrice, uint256 _vaultBalance) {
        return (total_users, total_deposited, total_withdraw, total_bnb, total_txs, total_airdrops, pistonTokenPriceFeed.getPrice(1), getVaultBalance());
    }

    /*************************** Airdrops ***************************/

    //@dev Send specified PISTON amount to given address
    function airdrop(address _to, uint256 _amount) external {

        address _addr = msg.sender;
        require(AIRDROP_ENABLED == true, "airdrops are disabled");
        require(_addr != _to, "self airdrop not allowed");
        require(_amount >= AIRDROP_MIN_AMOUNT, "minimum not reached");
        require(!HasUsedEject(msg.sender), "user used eject");
        require(users[_to].deposits < this.maxRollOf(usersRealDeposits[_to].deposits), "user already reached 5x of his real deposits");

        (uint256 _realizedAmount,) = calculateDepositTax(_amount);
        //This can only fail if the balance is insufficient
        require(
            pistonToken.transferFrom(
                _addr,
                address(this),
                _amount
            ),
            "PISTON to contract transfer failed; check balance and allowance."
        );

        //Make sure _to exists in the system; we increase
        require(users[_to].upline != address(0), "_to not found");

        (uint256 gross_payout,,,) = payoutOf(_to);

        users[_to].accumulatedDiv = gross_payout;

        //Fund to deposits (not a transfer)
        users[_to].deposits += _realizedAmount;
        users[_to].deposit_time = block.timestamp;

        //User statistics
        airdrops[_addr].airdrops += _realizedAmount;
        airdrops[_addr].last_airdrop = block.timestamp;
        airdrops[_to].airdrops_received += _realizedAmount;

        //Global Statistics
        total_airdrops += _realizedAmount;
        total_txs += 1;

        //Let em know!
        emit NewAirdrop(_addr, _to, _realizedAmount, block.timestamp);
        emit NewDeposit(_to, _realizedAmount);
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

interface ITokenMint {
    function mint(address beneficiary, uint256 tokenAmount) external returns (uint256);
}
interface ITokenPriceFeed {
    function getPrice(uint amount) external view returns(uint);
}
