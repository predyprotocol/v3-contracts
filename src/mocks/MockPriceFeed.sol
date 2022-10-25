// SPDX-License-Identifier: agpl-3.0
pragma solidity =0.7.6;

/**
 * @notice Mock of Chainlink price feed contract
 */
contract MockPriceFeed {
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    RoundData public latestRoundData;

    function setLatestRoundData(uint80 roundId, int256 answer) external {
        latestRoundData = RoundData(roundId, answer, block.timestamp, block.timestamp, 0);
    }
}
