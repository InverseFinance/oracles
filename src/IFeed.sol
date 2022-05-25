pragma solidity ^0.6.12;

interface IFeed {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (uint);
}
