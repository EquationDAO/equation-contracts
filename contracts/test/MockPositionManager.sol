// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../staking/interfaces/IUniswapV3Minimum.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract MockPositionManager is IPositionManagerMinimum, ERC721 {
    using Counters for Counters.Counter;

    address public EQU;
    address public WETH;
    Counters.Counter private _tokenIds;
    uint24 public fee = 3000;

    constructor(address _EQU, address _WETH) ERC721("MockV3PositionNFT", "V3-POS-NFT") {
        EQU = _EQU;
        WETH = _WETH;
    }

    function positions(
        uint256 /*_tokenID*/
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 _fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        return (
            0,
            0x0000000000000000000000000000000000000000,
            EQU,
            WETH,
            fee,
            -887220,
            887220,
            9999504443656554,
            0,
            0,
            0,
            0
        );
    }

    function mint(address _recipient) external returns (uint256 id) {
        _tokenIds.increment();
        id = _tokenIds.current();
        _mint(_recipient, id);
    }

    function setFee(uint24 _fee) external {
        fee = _fee;
    }
}
