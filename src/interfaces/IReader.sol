//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

interface IReader {
    function getPrice() external view returns (uint256);
}