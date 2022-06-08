pragma solidity >=0.6.0 <=0.8.14;

interface IStakeManager {
  function claimStaked() external;
  function token() external view returns (address);
  function stakedToken() external view returns (address);
}