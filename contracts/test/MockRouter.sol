// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../core/Pool.sol";
import "../governance/Governable.sol";

contract MockRouter is Governable {
    uint160 private tradePriceX96;
    uint256 private positionID = 1;
    uint128 private priceImpactFee;

    function setTradePriceX96(uint160 _tradePriceX96) external {
        tradePriceX96 = _tradePriceX96;
    }

    function setPositionID(uint256 _positionID) external {
        positionID = _positionID;
    }

    function setPriceImpactFee(uint128 _priceImpactFee) external {
        priceImpactFee = _priceImpactFee;
    }

    function pluginTransfer(IERC20 _token, address _from, address _to, uint256 _amount) external {
        SafeERC20.safeTransferFrom(_token, _from, _to, _amount);
    }

    function pluginOpenLiquidityPosition(
        IPool /*_pool*/,
        address /*_account*/,
        uint128 /*_margin*/,
        uint128 /*_liquidity*/
    ) external view returns (uint256) {
        return positionID;
    }

    function pluginCloseLiquidityPosition(
        IPool /*_pool*/,
        uint96 /*_positionID*/,
        address /*_receiver*/
    ) external view returns (uint128) {
        return priceImpactFee;
    }

    function pluginAdjustLiquidityPositionMargin(
        IPool /*_pool*/,
        uint96 /*_positionID*/,
        int128 /*_marginDelta*/,
        address /*_receiver*/
    ) external {}

    function pluginIncreasePosition(
        IPool /*_pool*/,
        address /*_account*/,
        Side /*_side*/,
        uint128 /*_marginDelta*/,
        uint128 /*_sizeDelta*/
    ) external view returns (uint160) {
        return (tradePriceX96);
    }

    function pluginDecreasePosition(
        IPool /*_pool*/,
        address /*_account*/,
        Side /*_side*/,
        uint128 /*_marginDelta*/,
        uint128 /*_sizeDelta*/,
        address /*_receiver*/
    ) external view returns (uint160) {
        return (tradePriceX96);
    }

    function pluginIncreaseRiskBufferFundPosition(
        IPool /*_pool*/,
        address /*_account*/,
        uint128 /*_liquidityDelta*/
    ) external {}

    function pluginDecreaseRiskBufferFundPosition(
        IPool /*_pool*/,
        address /*_account*/,
        uint128 /* _liquidityDelta*/,
        address /* _receiver*/
    ) external {}
}

/// @notice This is a mocked router that will drain all the available gas.
/// It's used to simulate a maliciously fabricated pool address passed in by the user
/// which will drain the gas
contract GasDrainingMockRouter {
    function drainGas() internal pure {
        while (true) {}
    }

    function pluginTransfer(IERC20 _token, address _from, address _to, uint256 _amount) external {
        SafeERC20.safeTransferFrom(_token, _from, _to, _amount);
    }

    function pluginOpenLiquidityPosition(
        IPool /*_pool*/,
        address /*_account*/,
        uint128 /*_margin*/,
        uint128 /*_liquidity*/
    ) external pure returns (uint256) {
        drainGas();
        return 0;
    }

    function pluginCloseLiquidityPosition(
        IPool /*_pool*/,
        uint96 /*_positionID*/,
        address /*_receiver*/
    ) external pure returns (uint128) {
        drainGas();
        return 0;
    }

    function pluginAdjustLiquidityPositionMargin(
        IPool /*_pool*/,
        uint96 /*_positionID*/,
        int128 /*_marginDelta*/,
        address /*_receiver*/
    ) external pure {
        drainGas();
    }

    function pluginIncreasePosition(
        IPool /*_pool*/,
        address /*_account*/,
        Side /*_side*/,
        uint128 /*_marginDelta*/,
        uint128 /*_sizeDelta*/
    ) external pure returns (uint160) {
        drainGas();
        return 0;
    }

    function pluginDecreasePosition(
        IPool /*_pool*/,
        address /*_account*/,
        Side /*_side*/,
        uint128 /*_marginDelta*/,
        uint128 /*_sizeDelta*/,
        address /*_receiver*/
    ) external pure returns (uint160) {
        drainGas();
        return 0;
    }

    function pluginIncreaseRiskBufferFundPosition(
        IPool /*_pool*/,
        address /*_account*/,
        uint128 /*_liquidityDelta*/
    ) external pure {
        drainGas();
    }

    function pluginDecreaseRiskBufferFundPosition(
        IPool /*_pool*/,
        address /*_account*/,
        uint128 /* _liquidityDelta*/,
        address /* _receiver*/
    ) external pure {
        drainGas();
    }
}
