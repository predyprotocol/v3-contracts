//SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.6;

interface IReader {
    function isMarginZero() external view returns (bool);

    function getPrice() external view returns (uint256);

    function getIndexPrice() external view returns (uint256);
}
