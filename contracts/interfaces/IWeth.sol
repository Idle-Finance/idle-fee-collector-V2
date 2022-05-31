pragma solidity >=0.6.0 <=0.8.14;

pragma solidity >=0.4.0;

interface IWETH {
    function balanceOf(address) external view returns (uint);
    function deposit() external payable;
    function approve(address guy, uint wad) external returns (bool);
    function transfer(address dst, uint wad) external returns (bool);
}