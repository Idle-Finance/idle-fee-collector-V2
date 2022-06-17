pragma solidity >=0.6.0 <=0.8.14;

interface IStakeManager {
  function claimStaked(bytes calldata _extraDatas) external;
  function stakedToken() external view returns (address);
  function withdrawAdmin(address _toAddress, uint256[] calldata _amounts) external;
}