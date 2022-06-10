// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <=0.8.14;

interface IDistributorProxy {
    function distribute(address gaugeAddress) external;
    function distribute_for(address gaugeAddress, address from) external;
    function toggle_approve_distribute(address distributingAddress) external;

}