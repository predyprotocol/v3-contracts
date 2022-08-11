// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import "./PredyMath.sol";
import "../Constants.sol";
import "./LPTMath.sol";
import "./BaseToken.sol";
import "./DataType.sol";

library VaultLib {
    using SafeMath for uint256;

    function depositLPT(DataType.Vault storage _vault, mapping(bytes32 => DataType.PerpStatus) storage ranges, bytes32 _rangeId, uint128 _liquidityAmount) external {
        // TODO: 同じrangeIdは同じところに代入する
        _vault.lpts.push(DataType.LPTState(
            true,
            _rangeId,
            _liquidityAmount,
            ranges[_rangeId].premiumGrowthForLender,
            ranges[_rangeId].fee0Growth,
            ranges[_rangeId].fee1Growth
        ));
    }

    function withdrawLPT(DataType.Vault storage _vault, mapping(bytes32 => DataType.PerpStatus) storage ranges, bytes32 _rangeId, uint128 _liquidityAmount) external {
        // TODO
    }

    function borrowLPT(DataType.Vault storage _vault, mapping(bytes32 => DataType.PerpStatus) storage ranges, bytes32 _rangeId, uint128 _liquidityAmount) external {
        // TODO: 同じrangeIdは同じところに代入する
        _vault.lpts.push(DataType.LPTState(
            false,
            _rangeId,
            _liquidityAmount,
            ranges[_rangeId].premiumGrowthForBorrower,
            0,
            0
        ));
    }

    function repayLPT(DataType.Vault storage _vault, mapping(bytes32 => DataType.PerpStatus) storage ranges, bytes32 _rangeId, uint128 _liquidityAmount) external {
        // TODO
    }


    function getCollateralPositionValue(
        DataType.Vault memory _vault,
        DataType.Context memory _context,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        BaseToken.TokenState memory _tokenState0,
        BaseToken.TokenState memory _tokenState1,
        uint160 _sqrtPrice
    )
        external
        view
        returns (uint256)
    {
        return 0;
    }
        

    function getCollateralPositionAmounts(
        DataType.Vault memory _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        BaseToken.TokenState memory _tokenState0,
        BaseToken.TokenState memory _tokenState1,
        uint160 _sqrtPrice
    )
        external
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        (totalAmount0, totalAmount1) = getLPTPositionAmounts(_vault, _ranges, _sqrtPrice, true);

        (uint256 fee0, uint256 fee1) = getEarnedTradeFee(_vault, _ranges);
        totalAmount0 = totalAmount0.add(fee0);
        totalAmount1 = totalAmount1.add(fee1);

        totalAmount0 = totalAmount0.add(BaseToken.getCollateralValue(_tokenState0, _vault.balance0));
        totalAmount1 = totalAmount1.add(BaseToken.getCollateralValue(_tokenState1, _vault.balance1));
    }

    function getDebtPositionAmounts(
        DataType.Vault memory _vault,
        mapping(bytes32 => DataType.PerpStatus) storage _ranges,
        BaseToken.TokenState memory _tokenState0,
        BaseToken.TokenState memory _tokenState1,
        uint160 _sqrtPrice
    )
        external
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        (totalAmount0, totalAmount1) = getLPTPositionAmounts(_vault, _ranges, _sqrtPrice, false);

        totalAmount0 = totalAmount0.add(BaseToken.getDebtValue(_tokenState0, _vault.balance0));
        totalAmount1 = totalAmount1.add(BaseToken.getDebtValue(_tokenState1, _vault.balance1));
    }

    function getLPTPositionAmounts(DataType.Vault memory vault, mapping(bytes32 => DataType.PerpStatus) storage ranges, uint160 _sqrtPrice, bool _isCollateral)
        internal
        view
        returns (uint256 totalAmount0, uint256 totalAmount1)
    {
        for (uint256 i = 0; i < vault.lpts.length; i++) {
            if (_isCollateral != vault.lpts[i].isCollateral) {
                continue;
            }

            (uint256 amount0, uint256 amount1) = LPTMath.getAmountsForLiquidity(
                _sqrtPrice,
                ranges[vault.lpts[i].rangeId].lowerTick,
                ranges[vault.lpts[i].rangeId].upperTick,
                vault.lpts[i].liquidityAmount
            );

            totalAmount0 = totalAmount0.add(amount0);
            totalAmount1 = totalAmount1.add(amount1);
        }
    }
    
    function getEarnedTradeFee(DataType.Vault memory vault, mapping(bytes32 => DataType.PerpStatus) storage ranges) public view returns (uint256 totalAmount0, uint256 totalAmount1) {
        for (uint256 i = 0; i < vault.lpts.length; i++) {
            if (!vault.lpts[i].isCollateral) {
                continue;
            }
            bytes32 rangeId = vault.lpts[i].rangeId;
            totalAmount0 = PredyMath.mulDiv((ranges[rangeId].fee0Growth.sub(vault.lpts[i].fee0Last)), vault.lpts[i].liquidityAmount, FixedPoint128.Q128);
            totalAmount1 = PredyMath.mulDiv((ranges[rangeId].fee1Growth.sub(vault.lpts[i].fee1Last)), vault.lpts[i].liquidityAmount, FixedPoint128.Q128);
        }
    }

    function getEarnedDailyPremium(DataType.Vault memory _vault, mapping(bytes32 => DataType.PerpStatus) storage ranges) external view returns(uint256 marginValue) {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            bytes32 rangeId = _vault.lpts[i].rangeId;
            DataType.PerpStatus memory perpStatus = ranges[rangeId];

            if (_vault.lpts[i].isCollateral) {
                marginValue = marginValue.add(
                    PredyMath.mulDiv((perpStatus.premiumGrowthForLender.sub(_vault.lpts[i].premiumGrowthLast)), _vault.lpts[i].liquidityAmount, 1e18)
                );
            }
        }
    }

    function getPaidDailyPremium(DataType.Vault memory _vault, mapping(bytes32 => DataType.PerpStatus) storage ranges) external view returns(uint256 marginValue) {
        for (uint256 i = 0; i < _vault.lpts.length; i++) {
            bytes32 rangeId = _vault.lpts[i].rangeId;
            DataType.PerpStatus memory perpStatus = ranges[rangeId];

            if (!_vault.lpts[i].isCollateral) {
                marginValue = marginValue.sub(
                    PredyMath.mulDiv((perpStatus.premiumGrowthForBorrower.sub(_vault.lpts[i].premiumGrowthLast)), _vault.lpts[i].liquidityAmount, 1e18)
                );
            }
        }
    }
}