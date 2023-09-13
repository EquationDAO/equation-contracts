// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../oracle/interfaces/IPriceFeed.sol";

contract MockChainLinkPriceFeed {
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }
    uint8 public decimals = 8;
    mapping(uint80 => RoundData) public roundDatas;
    uint80 public maxRound;

    function setDecimals(uint8 _decimals) external {
        decimals = _decimals;
    }

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory data = roundDatas[_roundId];
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    function setRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) external {
        RoundData memory data = RoundData({
            roundId: _roundId,
            answer: _answer,
            startedAt: _startedAt,
            updatedAt: _updatedAt,
            answeredInRound: _answeredInRound
        });
        if (_roundId > maxRound) {
            maxRound = _roundId;
        }
        roundDatas[_roundId] = data;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory data = roundDatas[maxRound];
        if (data.startedAt == 0) {
            return (data.roundId, data.answer, block.timestamp - 1, block.timestamp - 1, data.answeredInRound);
        }
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }
}
