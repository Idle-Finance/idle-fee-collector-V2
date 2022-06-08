pragma solidity = 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/ILiquidityGaugeV3.sol";
import "../interfaces/IIdleCDO.sol";
import "../interfaces/IStakeManager.sol";

contract StakeTranchesManager is IStakeManager , Ownable {
  using SafeERC20 for IERC20;

  ILiquidityGaugeV3 private immutable gauge;
  IERC20 private immutable underlingToken;
  IIdleCDO private immutable tranche;

  constructor (address _gauge, address _underlingToken, address _tranche) {
    gauge = ILiquidityGaugeV3(_gauge);
    underlingToken = IERC20(_underlingToken);
    tranche = IIdleCDO(_tranche);
  }

  function claimStaked() external onlyOwner {
    _claimStaked();
  }
  
  function _claimStaked() internal {
    uint256 balance = gauge.balanceOf(msg.sender);
    if (balance == 0) {
      return;
    }

    IERC20(address(gauge)).safeTransferFrom(msg.sender, address(this), balance);

    uint256 gaugeBalance  = gauge.balanceOf(address(this));
    gauge.withdraw(gaugeBalance, false);

    address _trancheAA = tranche.AATranche();
    uint256 _trancheAABalance = IERC20(_trancheAA).balanceOf(address(this));
    tranche.withdrawAA(_trancheAABalance);
    
    uint256 _underlingTokenBalance = underlingToken.balanceOf(address(this));
    underlingToken.safeTransfer(msg.sender, _underlingTokenBalance);
  }
  
  function token() external view returns (address) {
    return address(underlingToken);
  }
  function stakedToken() external view returns (address){
    return address(gauge);
  }

}