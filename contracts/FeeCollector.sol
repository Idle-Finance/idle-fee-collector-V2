// SPDX-License-Identifier: MIT
pragma solidity = 0.8.14;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IExchange.sol";
import "./interfaces/IStakeManager.sol";
import "./interfaces/IDistributorProxy.sol";

contract FeeCollector is Initializable, AccessControlUpgradeable {

  using SafeERC20Upgradeable for IERC20Upgradeable;

  struct StakeManager { 
    address _stakeManager;
    bool _isTrunchesToken;
   }
   
  IERC20Upgradeable private constant Weth = IERC20Upgradeable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  IDistributorProxy private constant DistributorProxy = IDistributorProxy(0x074306BC6a6Fc1bD02B425dd41D742ADf36Ca9C6);

  IExchange[] public ExchangeManagers;
  IStakeManager[] public StakeManagers;
  
  address[] private depositTokens;
  uint256[] private allocations; // 100_000 = 100%
  address[] private beneficiaries;

  mapping (address => bool) private beneficiariesExists;
  mapping (address => bool) private depositTokensExists;
  mapping (address => bool) private exchangeManagerExists;
  mapping (address => bool) private stakeManagerExists;

  uint8 public constant MAX_BENEFICIARIES = 5;
  uint8 public constant MIN_BENEFICIARIES = 1;
  uint8 public constant MAX_DEPOSIT_TOKENS = 15;
  uint256 public constant FULL_ALLOCATION = 100_000;

  bytes32 public constant WHITELISTED = keccak256("WHITELISTED_ROLE");

  event DepositTokens(address _depositor, uint256 _amountOut);

	// initializes exchange and skake managers
	// total beneficiaries' allocation should be 100%
  function initialize(
    address[] calldata _beneficiaries,
    uint256[] calldata _allocations,
    address[] calldata _initialDepositTokens,
    address[] calldata _exchangeManagers,
    StakeManager[] calldata _stakeManagers
  ) initializer public {
    
    // get managers
    _setExchangeManagers(_exchangeManagers);
    _setStakeManagers(_stakeManagers);

    // setup access control
    __AccessControl_init();
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(WHITELISTED, msg.sender);
    
    // setup beneficiaries and deposit tokens
    _setBeneficiaries(_beneficiaries, _allocations);
    _setDepositTokens(_initialDepositTokens);

  }

  // converts all registered fee tokens to WETH and deposits to
  // beneficiaries' based on split allocations
  function deposit(
    bool[] calldata _depositTokensEnabled,
    uint256[] calldata _minTokenOut,
    address[] calldata _managers,
    bytes[] calldata _data
  ) public onlyWhitelisted {
    _deposit(_depositTokensEnabled, _minTokenOut, _managers, _data);
  }


  // this method should be called with a staticCall as is not a view
  // that is because some exchange managers require non-view functions
  // to calculate the ouput amount
  // eg. https://docs.uniswap.org/protocol/reference/periphery/lens/Quoter 
  function previewDeposit(
    bool[] memory _depositTokensEnabled
  ) public returns(address [] memory, bytes[] memory)  {
    address[] memory _depositTokens = depositTokens;
    require(_depositTokensEnabled.length ==  _depositTokens.length, "Invalid length");

    IExchange[] memory _exchangeManagers = ExchangeManagers;
    IERC20Upgradeable _tokenInterface;
    uint256 _maxAmountOut;
    uint256 _currentAmountOut;
    uint256 _currentBalance;
    uint256 _exchangeManagerIndex;
    bytes memory _amountOutData;

    bytes[] memory _data = new bytes[](_depositTokensEnabled.length);
    address [] memory _managers = new address[](_depositTokensEnabled.length);

    for (uint256 i = 0; i <  _depositTokens.length; ++i) {
      if (_depositTokensEnabled[i] == false) {continue;}

      _tokenInterface = IERC20Upgradeable(_depositTokens[i]);
      _currentBalance = _tokenInterface.balanceOf(address(this));
      _maxAmountOut = 0;

      for (uint256 y = 0; y < _exchangeManagers.length; ++y) {
        (_currentAmountOut, _amountOutData) = _exchangeManagers[y].getAmoutOut(address(_tokenInterface), address(Weth), _currentBalance);
        if (_currentAmountOut > _maxAmountOut) {
          _maxAmountOut = _currentAmountOut;
          _exchangeManagerIndex = y;
        }
      }
      _managers[i] = address(_exchangeManagers[_exchangeManagerIndex]);
      _data[i] = _amountOutData;
    }
    return (_managers, _data);

  }

	// cannot set an existing exchange manager
	// also approve the exchange manager to use all deposit tokens
  function addExchangeManager(address exchangeAddress) external onlyAdmin {
    require(exchangeManagerExists[exchangeAddress] == false, "Duplicate exchange manager");
    require(exchangeAddress != address(0), "Exchange Manager cannot be 0 address");
    
    IExchange exchange = IExchange(exchangeAddress);
    ExchangeManagers.push(exchange);
    exchangeManagerExists[exchangeAddress] = true;
  }

	// replaces the last exchange manager with the one on the given index
	// also removes exchange manager approval of deposit tokens
  function removeExchangeManager(uint256 _index) external onlyAdmin {
    IExchange[] memory _exchangeManagers = ExchangeManagers;
    require(_exchangeManagers.length > _index, "Invaild index");
    require(_exchangeManagers.length > 1, "Cannot remove the last exchange");

    IExchange exchange = _exchangeManagers[_index];
    exchangeManagerExists[address(exchange)] = false;

    ExchangeManagers[_index] = _exchangeManagers[_exchangeManagers.length-1];
    ExchangeManagers.pop();
  }

	// cannot set an existing stake manager
  function addStakeManager(StakeManager calldata _stake) external onlyAdmin {
    require(stakeManagerExists[_stake._stakeManager] == false, "Duplicate stake manager");
    require(_stake._stakeManager != address(0), "Steke Manager cannot be 0 address");

    if (_stake._isTrunchesToken) {
      DistributorProxy.toggle_approve_distribute(_stake._stakeManager);
    }
    
    IStakeManager stake = IStakeManager(_stake._stakeManager);
    StakeManagers.push(stake);
    stakeManagerExists[_stake._stakeManager] = true;
  }

	// replaces the last stake manager with the one on the given index
  function removeStakeManager(uint256 _index) external onlyAdmin {
    IStakeManager[] memory _stakeManagers = StakeManagers;
    require(_stakeManagers.length > _index, "Invaild index");
    require(_stakeManagers.length > 1, "Cannot remove the last stake manager");

    IStakeManager stake = _stakeManagers[_index];
    stakeManagerExists[address(stake)] = false;

    StakeManagers[_index] = _stakeManagers[_stakeManagers.length-1];
    StakeManagers.pop();
  }

	// find the respective stake manager for each unstake token
	// and unstakes / starts cooldown for that token
  function claimStakedToken(address[] calldata _unstakeTokens) external onlyAdmin {
    _claimStakedToken(_unstakeTokens);
  }

	// note: call `deposit()` before this function to clear up accrued fees with previous allocations
  // the split allocations must sum to 100000.
  function setSplitAllocation(uint256[] calldata _allocations) external onlyAdmin {

    _setSplitAllocation(_allocations);
  }

  // note: call `deposit()` before this function to clear up accrued fees with the previous beneficiaries' setup
  // the new allocations must include the new beneficiary
  // there's also a maximum of 5 beneficiaries
  function addBeneficiaryAddress(address _newBeneficiary, uint256[] calldata _newAllocation) external onlyAdmin {
    require(beneficiaries.length < MAX_BENEFICIARIES, "Max beneficiaries");
    require(_newBeneficiary != address(0), "Beneficiary cannot be 0 address");

    require(beneficiariesExists[_newBeneficiary] == false, "Duplicate beneficiary");
    beneficiariesExists[_newBeneficiary] = true;

    beneficiaries.push(_newBeneficiary);

    _setSplitAllocation(_newAllocation);
  }

  // note: call `deposit()` before this function to clear up accrued fees with the previous beneficiaries' setup
  // the beneficiary at the last index, will be replaced with the beneficiary at a given index
  function removeBeneficiaryAt(uint256 _index, uint256[] calldata _newAllocation) external onlyAdmin {
    address[] memory _beneficiaries = beneficiaries;
    require(_index < _beneficiaries.length, "Out of range");
    require(_beneficiaries.length > MIN_BENEFICIARIES, "Min beneficiaries");

    beneficiaries[_index] = _beneficiaries[_beneficiaries.length-1];
    beneficiaries.pop();

    beneficiariesExists[_beneficiaries[_index]] = false;
    
    _setSplitAllocation(_newAllocation);
  }

	// this is used for calling deposit at the momemnt
  function addAddressToWhiteList(address _addressToAdd) external onlyAdmin{
    grantRole(WHITELISTED, _addressToAdd);
  }

  function removeAddressFromWhiteList(address _addressToRemove) external onlyAdmin {
    revokeRole(WHITELISTED, _addressToRemove);
  }
  
  // respects the of 15 fee tokens than can be registered
  // WETH cannot be accepted as a fee token
  function registerTokenToDepositList(address _tokenAddress) external onlyAdmin {
    require(depositTokens.length < MAX_DEPOSIT_TOKENS, "Too many tokens");
    require(_tokenAddress != address(0), "Token cannot be 0 address");
    require(_tokenAddress != address(Weth), "WETH not supported"); // as there is no WETH to WETH pool in some exchanges
    require(depositTokensExists[_tokenAddress] == false, "Duplicate deposit token");
    depositTokensExists[_tokenAddress] = true;
    depositTokens.push(_tokenAddress);
  }

  function removeTokenFromDepositList(uint256 _index) external onlyAdmin {
    address[] memory _depositTokens = depositTokens;
    depositTokensExists[address(_depositTokens[_index])] = false;
    depositTokens[_index] = _depositTokens[_depositTokens.length - 1];
    depositTokens.pop();
  }

	// moves a specific token to a given address for a given amount
  function withdraw(address _token, address _toAddress, uint256 _amount) external onlyAdmin {
    IERC20Upgradeable(_token).safeTransfer(_toAddress, _amount);
  }

	// there can only be one admin
	// this is different from the proxy admin of the contract
  function replaceAdmin(address _newAdmin) external onlyAdmin {
    grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
    revokeRole(DEFAULT_ADMIN_ROLE, msg.sender); 
  }

	/***********************/
	/*****  INTERNAL   *****/
	/***********************/

	function _setStakeManagers(StakeManager[] calldata _stakeManagers) internal {
    for (uint256 index = 0; index < _stakeManagers.length; ++index) {
      require(stakeManagerExists[_stakeManagers[index]._stakeManager] == false, "Duplicate stake manager");
      require(_stakeManagers[index]._stakeManager != address(0), "Stake Manager cannot be 0 address");
      if (_stakeManagers[index]._isTrunchesToken) {
        DistributorProxy.toggle_approve_distribute(_stakeManagers[index]._stakeManager);
      }
      stakeManagerExists[_stakeManagers[index]._stakeManager] = true;
      StakeManagers.push(IStakeManager(_stakeManagers[index]._stakeManager));
    }
  }

  function _setExchangeManagers(address[] calldata _exchangeManagers) internal {
    for (uint256 index = 0; index < _exchangeManagers.length; ++index) {
      require(exchangeManagerExists[_exchangeManagers[index]] == false, "Duplicate exchange manager");
      require(_exchangeManagers[index] != address(0), "Exchange Manager cannot be 0 address");
      exchangeManagerExists[_exchangeManagers[index]] = true; 
      ExchangeManagers.push(IExchange(_exchangeManagers[index]));
    }
  }

  function _setBeneficiaries(address[] calldata _beneficiaries, uint256[] calldata _allocations) internal {
    require(_beneficiaries.length == _allocations.length, "Allocations length != beneficiaries length");
    require(_beneficiaries.length <= MAX_BENEFICIARIES);

    uint256 totalAllocation = 0;
    for (uint256 index = 0; index < _beneficiaries.length; ++index) {
      require(beneficiariesExists[_beneficiaries[index]] == false, "Duplicate beneficiary");
      require(_beneficiaries[index] != address(0), "Beneficiary cannot be 0 address");
      beneficiaries.push(_beneficiaries[index]);
      allocations.push(_allocations[index]);
      totalAllocation = totalAllocation + _allocations[index];
      beneficiariesExists[_beneficiaries[index]] = true;
    }
    require(totalAllocation == FULL_ALLOCATION, "Ratio does not equal 100000");
  }

  function _setDepositTokens(address[] calldata _initialDepositTokens) internal {
    require(_initialDepositTokens.length <= MAX_DEPOSIT_TOKENS);

    address _depositToken;
    for (uint256 index = 0; index < _initialDepositTokens.length; ++index) {
      _depositToken = _initialDepositTokens[index];
      require(_depositToken != address(0), "Token cannot be 0 address");
      require(_depositToken != address(Weth), "WETH not supported");
      require(depositTokensExists[_depositToken] == false, "Duplicate deposit token");
      depositTokensExists[_depositToken] = true;
      depositTokens.push(_depositToken);
    }
  }

	function _deposit(
    bool[] memory _depositTokensEnabled,
    uint256[] memory _minTokenOut,
    address[] memory _managers,
    bytes[] memory _amountOutData
  ) internal {
    address[] memory _depositTokens = depositTokens;
    require(_depositTokensEnabled.length == _depositTokens.length, "Invalid length");
    require(_minTokenOut.length == _depositTokens.length, "Invalid length");

    IERC20Upgradeable _tokenInterface;
    IExchange manager;

    uint256 _tokenBalance;

    address[] memory path = new address[](2);
    path[1] = address(Weth);

    for (uint256 index = 0; index < _depositTokens.length; ++index) {
      if (_depositTokensEnabled[index] == false) {continue;}

      _tokenInterface = IERC20Upgradeable(_depositTokens[index]);

      _tokenBalance = _tokenInterface.balanceOf(address(this));

      manager = IExchange(_managers[index]);

      if (_tokenBalance > 0) {
        _tokenInterface.safeTransfer(address(manager), _tokenBalance);

        path[0] = address(_tokenInterface);

        manager.exchange(
          address(_tokenInterface),
          _minTokenOut[index],
          address(this),
          path,
          _amountOutData[index]
        );

      }
    }

    uint256 _wethBalance = Weth.balanceOf(address(this));
    uint256[] memory _allocations = allocations;

    if (_wethBalance > 0){
      uint256[] memory wethBalanceToken = _amountsFromAllocations(_allocations, _wethBalance);

      for (uint256 index = 0; index < _allocations.length; ++index){
        Weth.safeTransfer(beneficiaries[index], wethBalanceToken[index]);
      }
    }
    emit DepositTokens(msg.sender, _wethBalance);
  }

  function _setSplitAllocation(uint256[] calldata _allocations) internal {
    require(_allocations.length == beneficiaries.length, "Invalid length");
    
    uint256 _totalAllocation = 0;
    for (uint256 i = 0; i < _allocations.length; ++i) {
      _totalAllocation += _allocations[i];
    }

    require(_totalAllocation == FULL_ALLOCATION, "Ratio does not equal 100000");

    allocations = _allocations;
  }

  function _amountsFromAllocations(uint256[] memory _allocations, uint256 totalBalanceWeth) internal pure returns (uint256[] memory) {
    uint256 currentBalanceWeth;
    uint256 allocatedBalanceWeth;

    uint256[] memory amountWeth = new uint256[](_allocations.length);

    for (uint256 i = 0; i < _allocations.length; ++i) {
      if (i == _allocations.length - 1) {
        amountWeth[i] = totalBalanceWeth - allocatedBalanceWeth;
      } else {
        currentBalanceWeth = (totalBalanceWeth * _allocations[i]) / FULL_ALLOCATION;
        allocatedBalanceWeth += currentBalanceWeth;
        amountWeth[i] = currentBalanceWeth;
      }
    }
    return amountWeth;
  }

  function _claimStakedToken(address[] calldata _unstakeTokens) internal {
    IStakeManager[] memory _stakeManagers = StakeManagers;
    IERC20Upgradeable unstakeToken;
    uint256 tokenBalance;

    for (uint256 i = 0; i < _stakeManagers.length; ++i) {
      for (uint256 y = 0; y < _unstakeTokens.length; ++y) {
        if (_stakeManagers[i].stakedToken() == _unstakeTokens[y]) {
          unstakeToken = IERC20Upgradeable(_unstakeTokens[y]);
          tokenBalance = unstakeToken.balanceOf(address(this));
          
          unstakeToken.safeApprove(address(_stakeManagers[i]), tokenBalance);
          _stakeManagers[i].claimStaked();
          unstakeToken.safeApprove(address(_stakeManagers[i]), 0);
          break;
        }
      }
    }

  }



	/***********************/
	/*****  MODIFIERS  *****/
	/***********************/

  modifier onlyAdmin {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Unauthorised: Not admin");
    _;
  }

  modifier onlyWhitelisted {
    require(hasRole(WHITELISTED, msg.sender), "Unauthorised: Not whitelisted");
    _;
  }


	/***********************/
	/*****  VIEWS      *****/
	/***********************/

  function getSplitAllocation() external view returns (uint256[] memory) { return (allocations); }

  function isAddressWhitelisted(address _address) external view returns (bool) {return (hasRole(WHITELISTED, _address)); }
  function isAddressAdmin(address _address) external view returns (bool) {return (hasRole(DEFAULT_ADMIN_ROLE, _address)); }

  function getBeneficiaries() external view returns (address[] memory) { return (beneficiaries); }

  function isTokenInDespositList(address _tokenAddress) external view returns (bool) {return depositTokensExists[_tokenAddress]; }

  function getNumTokensInDepositList() external view returns (uint256) {return (depositTokens.length);}

  function getDepositTokens() external view returns (address[] memory) {
    return depositTokens;
  }

  function getExchangeManagers()public view returns(IExchange [] memory){
    return ExchangeManagers;
  }

  function getStakeeManagers()public view returns(IStakeManager [] memory){
    return StakeManagers;
  }
}