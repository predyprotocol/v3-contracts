// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "./DataType.sol";

library LPTStateLib {
    using SafeMath for uint256;

    /**
     * @notice register new LPT
     */
    function registerNewLPTState(DataType.PerpStatus storage _range, uint256 _tokenId, int24 _lowerTick, int24 _upperTick) external {
        _range.tokenId = _tokenId;
        _range.lowerTick = _lowerTick;
        _range.upperTick = _upperTick;
        _range.lastTouchedTimestamp = block.timestamp;
    }


    function getRangeKey(int24 _lower, int24 _upper) internal pure returns (bytes32) {
        return keccak256(abi.encode(_lower, _upper));
    }
}