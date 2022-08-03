// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../Constants.sol";

library VaultLib {
    using SafeMath for uint256;

    struct PerpStatus {
        uint256 tokenId;
        int24 lower;
        int24 upper;
        uint128 borrowedLiquidity;
        uint256 cumulativeFee;
        uint256 cumulativeFeeForLP;
        uint256 cumFee0;
        uint256 cumFee1;
        uint256 lastTouchedTimestamp;
    }
    struct Vault {
        uint256 margin;
        uint256 collateralAmount0;
        uint256 collateralAmount1;
        bool[] isCollateral;
        bytes32[] lptIndex;
        uint128[] lptLiquidity;
        uint256[] lptFeeGrowth;
    }

    function setMargin(Vault storage _vault, uint256 _margin) external {
        _vault.margin = _margin;
    }

    function getMarginValue(Vault memory _vault, mapping(bytes32 => PerpStatus) storage ranges, uint256 _margin) external view returns(uint256 marginValue) {
        marginValue = _vault.margin;

        for (uint256 i = 0; i < _vault.lptIndex.length; i++) {
            bytes32 rangeId = _vault.lptIndex[i];
            VaultLib.PerpStatus memory perpStatus = ranges[rangeId];

            if (_vault.isCollateral[i]) {
                marginValue = marginValue.add(
                    ((perpStatus.cumulativeFeeForLP.sub(_vault.lptFeeGrowth[i])) * _vault.lptLiquidity[i]) / 1e18
                );
            } else {
                marginValue = marginValue.sub(
                    ((perpStatus.cumulativeFee.sub(_vault.lptFeeGrowth[i])) * _vault.lptLiquidity[i]) / 1e18
                );
            }
        }
    }
}