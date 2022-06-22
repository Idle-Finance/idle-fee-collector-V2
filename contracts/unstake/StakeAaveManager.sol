pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IStakedAave.sol";
import "../interfaces/IStakeManager.sol";

contract StakeAaveManager is IStakeManager , Ownable {
  using SafeERC20 for IERC20;

  IERC20 private immutable Aave;
  IStakedAave private immutable StkAave;

  constructor (address _aave, address _stakeAave) {
    StkAave = IStakedAave(_stakeAave);
    Aave = IERC20(_aave);
  }

  function COOLDOWN_SECONDS() external view onlyOwner returns (uint256) {
    return StkAave.COOLDOWN_SECONDS();
  }

  function claimStaked(StakeToken[] calldata _stakeTokens) external override onlyOwner {
    _claimStkAave();
  }

  function withdrawAdmin(address _stakeToken, address _toAddress, uint256[] calldata _amounts) external override onlyOwner {
    IERC20[2] memory _tokens = [Aave, IERC20(address(StkAave))];
    for (uint256 index = 0; index < _tokens.length; ++index) {
      if(_amounts[index] == 0) {continue;}
      _tokens[index].safeTransfer(_toAddress, _amounts[index]);
    }
  }

  function addStakedToken(address _gauge, address _tranche, address[] calldata _underlyingTokens, address _pool, address _lpTokens) external override onlyOwner {}

  function removeStakedToken(uint256 _index, address _gauge) external override onlyOwner {}

  function _claimStkAave() internal {
    uint256 _stakersCooldown = StkAave.stakersCooldowns(address(this));
      // If there is a pending cooldown:
    if (_stakersCooldown > 0) {
      uint256 _cooldownEnd = _stakersCooldown + StkAave.COOLDOWN_SECONDS();
      // If it is over
      if (_cooldownEnd < block.timestamp) {
        // If the unstake window is active
        if (block.timestamp - _cooldownEnd <= StkAave.UNSTAKE_WINDOW()) {
          // redeem stkAave AND begin new cooldown
          StkAave.redeem(address(this), type(uint256).max);

          uint256 aaveBalance =  Aave.balanceOf(address(this));
          Aave.safeTransfer(msg.sender, aaveBalance);
        }
      } else {
        // If it is not over, do nothing
        return;
      }
    }
    
    uint256 stkAaveBalance  = StkAave.balanceOf(msg.sender);
    if (stkAaveBalance >  0 ) {
      IERC20(address(StkAave)).safeTransferFrom(msg.sender, address(this), stkAaveBalance);
    }

    // If there's no pending cooldown or we just redeem the prev locked rewards,
    // then begin a new cooldown
    if (StkAave.balanceOf(address(this)) > 0) {
      // start a new cooldown
      StkAave.cooldown();
    }
  }

  function stakedTokens() view external override returns(address[] memory) {
    address[] memory _stakedTokens = new address[](1);
    _stakedTokens[0] = address(StkAave);
    return _stakedTokens;
  }
}