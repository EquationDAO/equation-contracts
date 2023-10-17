// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "../plugins/Router.sol";
import "../libraries/Constants.sol";
import "../libraries/SafeCast.sol";
import "../libraries/ReentrancyGuard.sol";
import {M as Math} from "../libraries/Math.sol";
import "./interfaces/IUniswapV3Minimum.sol";
import "./interfaces/IFeeDistributorCallback.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/contracts/libraries/SqrtPriceMath.sol";
import "@uniswap/v4-core/contracts/libraries/TickMath.sol";

contract FeeDistributor is IFeeDistributor, IFeeDistributorCallback, ReentrancyGuard, Governable, ERC721Holder {
    using SafeMath for *;
    using SafeCast for *;
    using SafeERC20 for IERC20;

    bytes32 internal constant V3_POOL_INIT_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    IEFC private immutable EFC;
    IERC20 private immutable EQU;
    IERC20 private immutable WETH;
    IERC20 private immutable veEQU;
    Router private immutable router;
    IUniswapV3PoolFactoryMinimum private immutable v3PoolFactory;
    IPositionManagerMinimum private immutable v3PositionManager;
    /// @dev Indicates whether the EQU token is token0 or token1 in the Uniswap V3 Pool
    bool private immutable isToken0;
    /// @inheritdoc IFeeDistributor
    IERC20 public immutable override feeToken;
    /// @inheritdoc IFeeDistributor
    uint16 public immutable override withdrawalPeriod;

    /// @inheritdoc IFeeDistributor
    uint256 public override totalStakedWithMultiplier;
    /// @dev The serial number of the next stake info, starting from 1
    uint80 private stakeIDNext;
    /// @inheritdoc IFeeDistributor
    uint16 public override mintedArchitects;
    /// @inheritdoc IFeeDistributor
    uint160 public override architectPerShareGrowthX64;
    /// @inheritdoc IFeeDistributor
    uint96 public override feeBalance;
    /// @inheritdoc IFeeDistributor
    uint160 public override perShareGrowthX64;
    /// @inheritdoc IFeeDistributor
    mapping(address => mapping(uint256 => StakeInfo)) public override stakeInfos;
    /// @inheritdoc IFeeDistributor
    mapping(address => mapping(uint256 => StakeInfo)) public override v3PosStakeInfos;
    /// @inheritdoc IFeeDistributor
    mapping(uint256 => uint160) public override architectPerShareGrowthX64s;
    /// @inheritdoc IFeeDistributor
    mapping(uint16 => uint16) public override lockupRewardMultipliers;

    modifier onlyRouter() {
        if (msg.sender != address(router)) revert InvalidCaller(msg.sender);
        _;
    }

    modifier onlyEFC() {
        if (msg.sender != address(EFC)) revert InvalidCaller(msg.sender);
        _;
    }

    constructor(
        IEFC _EFC,
        IERC20 _EQU,
        IERC20 _WETH,
        IERC20 _veEQU,
        IERC20 _feeToken,
        Router _router,
        IUniswapV3PoolFactoryMinimum _v3PoolFactory,
        IPositionManagerMinimum _v3PositionManager,
        uint16 _withdrawalPeriod
    ) {
        EFC = _EFC;
        EQU = _EQU;
        WETH = _WETH;
        veEQU = _veEQU;
        feeToken = _feeToken;
        router = _router;
        v3PoolFactory = _v3PoolFactory;
        v3PositionManager = _v3PositionManager;
        withdrawalPeriod = _withdrawalPeriod;

        isToken0 = address(EQU) < address(WETH);
    }

    /// @inheritdoc IFeeDistributor
    function setLockupRewardMultipliers(
        LockupRewardMultiplierParameter[] calldata _lockupRewardMultiplierParameters
    ) external override nonReentrant onlyGov {
        for (uint256 i; i < _lockupRewardMultiplierParameters.length; ++i) {
            lockupRewardMultipliers[_lockupRewardMultiplierParameters[i].period] = _lockupRewardMultiplierParameters[i]
                .multiplier;
        }
        emit LockupRewardMultipliersSet(_lockupRewardMultiplierParameters);
    }

    /// @inheritdoc IFeeDistributor
    function depositFee(uint256 _amount) external override nonReentrant {
        if (mintedArchitects == 0 || totalStakedWithMultiplier == 0) revert DepositConditionNotMet();

        feeBalance = (feeBalance + _amount).toUint96();
        uint256 balance = feeToken.balanceOf(address(this));
        if (balance < feeBalance) revert DepositAmountIsGreaterThanTheTransfer(feeBalance, balance);

        (uint256 equFeeAmount, uint256 architectFeeAmount) = _allocateFee(_amount);
        perShareGrowthX64 += Math.mulDiv(equFeeAmount, Constants.Q64, totalStakedWithMultiplier).toUint160();
        architectPerShareGrowthX64 += Math.mulDiv(architectFeeAmount, Constants.Q64, mintedArchitects).toUint160();
        emit FeeDeposited(_amount, equFeeAmount, architectFeeAmount, perShareGrowthX64, architectPerShareGrowthX64);
    }

    /// @inheritdoc IFeeDistributor
    function stake(uint256 _amount, address _receiver, uint16 _period) external override nonReentrant {
        EQU.safeTransferFrom(msg.sender, address(this), _amount);

        uint80 id = ++stakeIDNext;
        _stake(stakeInfos, _receiver, id, _amount, _period);

        emit Staked(msg.sender, _receiver, id, _amount, _period);
    }

    /// @inheritdoc IFeeDistributor
    function stakeV3Pos(uint256 _id, address _receiver, uint16 _period) external override nonReentrant {
        uint256 amount = uint256(_calculateEQUAmount(_id));
        if (amount == 0) revert ExchangeableEQUAmountIsZero();

        IERC721(address(v3PositionManager)).safeTransferFrom(msg.sender, address(this), _id);

        _stake(v3PosStakeInfos, _receiver, _id, amount, _period);

        emit V3PosStaked(msg.sender, _receiver, _id, amount, _period);
    }

    /// @inheritdoc IFeeDistributor
    function unstake(
        uint256[] calldata _ids,
        address _receiver
    ) external override nonReentrant returns (uint256 rewardAmount) {
        uint256 totalStakedAmount;

        (rewardAmount, totalStakedAmount) = _unstakeBatch(stakeInfos, msg.sender, _receiver, _ids, _unstake);

        EQU.safeTransfer(_receiver, totalStakedAmount);
    }

    /// @inheritdoc IFeeDistributor
    function unstakeV3Pos(
        uint256[] calldata _ids,
        address _receiver
    ) external override nonReentrant returns (uint256 rewardAmount) {
        (rewardAmount, ) = _unstakeBatch(v3PosStakeInfos, msg.sender, _receiver, _ids, _unstakeV3Pos);
    }

    /// @inheritdoc IFeeDistributorCallback
    function onMintArchitect(uint256 _tokenID) external override onlyEFC nonReentrant {
        architectPerShareGrowthX64s[_tokenID] = architectPerShareGrowthX64;
        // Because the total amount of Architect type NFTs is at most 100, it will never overflow here.
        // prettier-ignore
        unchecked { ++mintedArchitects; }
    }

    /// @inheritdoc IFeeDistributor
    function collectBatchByRouter(
        address _owner,
        address _receiver,
        uint256[] calldata _ids
    ) external override onlyRouter nonReentrant returns (uint256 rewardAmount) {
        rewardAmount = _collectBatch(_owner, _receiver, _ids, _collectEQUWithoutTransfer);
    }

    /// @inheritdoc IFeeDistributor
    function collectV3PosBatchByRouter(
        address _owner,
        address _receiver,
        uint256[] calldata _ids
    ) external override onlyRouter nonReentrant returns (uint256 rewardAmount) {
        rewardAmount = _collectBatch(_owner, _receiver, _ids, _collectV3PosWithoutTransfer);
    }

    /// @inheritdoc IFeeDistributor
    function collectArchitectBatchByRouter(
        address _receiver,
        uint256[] calldata _tokenIDs
    ) external override onlyRouter nonReentrant returns (uint256 rewardAmount) {
        rewardAmount = _collectArchitectBatch(_receiver, _tokenIDs);
    }

    /// @inheritdoc IFeeDistributor
    function collectBatch(
        address _receiver,
        uint256[] calldata _ids
    ) public override nonReentrant returns (uint256 rewardAmount) {
        rewardAmount = _collectBatch(msg.sender, _receiver, _ids, _collectEQUWithoutTransfer);
    }

    /// @inheritdoc IFeeDistributor
    function collectV3PosBatch(
        address _receiver,
        uint256[] calldata _ids
    ) public override nonReentrant returns (uint256 rewardAmount) {
        rewardAmount = _collectBatch(msg.sender, _receiver, _ids, _collectV3PosWithoutTransfer);
    }

    /// @inheritdoc IFeeDistributor
    function collectArchitectBatch(
        address _receiver,
        uint256[] calldata _tokenIDs
    ) public override nonReentrant returns (uint256 rewardAmount) {
        for (uint256 i; i < _tokenIDs.length; ++i)
            if (msg.sender != EFC.ownerOf(_tokenIDs[i])) revert InvalidNFTOwner(msg.sender, _tokenIDs[i]);
        rewardAmount = _collectArchitectBatch(_receiver, _tokenIDs);
    }

    function _stake(
        mapping(address => mapping(uint256 => StakeInfo)) storage _stakeInfos,
        address _receiver,
        uint256 _id,
        uint256 _amount,
        uint16 _period
    ) private {
        uint16 multiplier = lockupRewardMultipliers[_period];
        if (multiplier == 0) revert InvalidLockupPeriod(_period);

        _stakeInfos[_receiver][_id] = StakeInfo({
            amount: _amount,
            lockupStartTime: block.timestamp.toUint64(),
            multiplier: multiplier,
            period: _period,
            perShareGrowthX64: perShareGrowthX64
        });

        // The value 0x40c10f19 represents the function selector for the 'mint(address,uint256)' function.
        Address.functionCall(address(veEQU), abi.encodeWithSelector(0x40c10f19, _receiver, _amount));

        // Because the total amount of EQU issued is 10 million, it will never overflow here.
        // prettier-ignore
        unchecked { totalStakedWithMultiplier += _amount * multiplier; }
    }

    function _unstakeBatch(
        mapping(address => mapping(uint256 => StakeInfo)) storage _stakeInfos,
        address _owner,
        address _receiver,
        uint256[] calldata _ids,
        function(address, address, uint256, uint256) internal returns (uint256) _op
    ) private returns (uint256 rewardAmount, uint256 totalStakedAmount) {
        uint256 id;
        uint256 amount;
        StakeInfo memory stakeInfoCache;
        uint256 totalStakedWithMultiplierDelta;
        unchecked {
            for (uint256 i; i < _ids.length; ++i) {
                id = _ids[i];

                stakeInfoCache = _stakeInfos[_owner][id];
                _validateStakeInfo(id, stakeInfoCache.lockupStartTime, stakeInfoCache.period);

                // Because the total amount of EQU issued is 10 million, it will never overflow here.
                totalStakedAmount += stakeInfoCache.amount;
                totalStakedWithMultiplierDelta += stakeInfoCache.amount * stakeInfoCache.multiplier;

                amount = _op(_owner, _receiver, id, stakeInfoCache.amount);

                delete _stakeInfos[_owner][id];
                rewardAmount = rewardAmount.add(amount);
            }
            totalStakedWithMultiplier -= totalStakedWithMultiplierDelta;
        }

        _transferOutAndUpdateFeeBalance(_receiver, rewardAmount);
        // The value 0x9dc29fac represents the function selector for the 'burn(address,uint256)' function.
        Address.functionCall(address(veEQU), abi.encodeWithSelector(0x9dc29fac, _owner, totalStakedAmount));
    }

    function _unstakeV3Pos(
        address _owner,
        address _receiver,
        uint256 _id,
        uint256 _unstakeAmount
    ) internal returns (uint256 rewardAmount) {
        rewardAmount = _collectWithoutTransfer(v3PosStakeInfos, _owner, _id);
        IERC721(address(v3PositionManager)).safeTransferFrom(address(this), _receiver, _id);
        emit V3PosUnstaked(_owner, _receiver, _id, _unstakeAmount, rewardAmount);
    }

    function _unstake(
        address _owner,
        address _receiver,
        uint256 _id,
        uint256 _unstakeAmount
    ) internal returns (uint256 rewardAmount) {
        rewardAmount = _collectWithoutTransfer(stakeInfos, _owner, _id);
        emit Unstaked(_owner, _receiver, _id, _unstakeAmount, rewardAmount);
    }

    function _collectBatch(
        address _owner,
        address _receiver,
        uint256[] calldata _ids,
        function(address, address, uint256) internal returns (uint256) _op
    ) private returns (uint256 rewardAmount) {
        uint256 id;
        uint256 amount;
        for (uint256 i; i < _ids.length; ++i) {
            id = _ids[i];

            amount = _op(_owner, _receiver, id);

            rewardAmount += amount;
        }

        _transferOutAndUpdateFeeBalance(_receiver, rewardAmount);
    }

    function _collectV3PosWithoutTransfer(
        address _owner,
        address _receiver,
        uint256 _id
    ) internal returns (uint256 rewardAmount) {
        rewardAmount = _collectWithoutTransfer(v3PosStakeInfos, _owner, _id);
        emit V3PosCollected(_owner, _receiver, _id, rewardAmount);
    }

    function _collectEQUWithoutTransfer(
        address _owner,
        address _receiver,
        uint256 _id
    ) internal returns (uint256 rewardAmount) {
        rewardAmount = _collectWithoutTransfer(stakeInfos, _owner, _id);
        emit Collected(_owner, _receiver, _id, rewardAmount);
    }

    function _collectWithoutTransfer(
        mapping(address => mapping(uint256 => StakeInfo)) storage _stakeInfos,
        address _owner,
        uint256 _id
    ) private returns (uint256 amount) {
        StakeInfo memory stakeInfoCache = _stakeInfos[_owner][_id];
        unchecked {
            // Because the total amount of EQU issued is 10 million, it will never overflow here.
            amount = Math.mulDiv(
                perShareGrowthX64 - stakeInfoCache.perShareGrowthX64,
                stakeInfoCache.amount * stakeInfoCache.multiplier,
                Constants.Q64
            );
            _stakeInfos[_owner][_id].perShareGrowthX64 = perShareGrowthX64;
        }
    }

    function _collectArchitectBatch(
        address _receiver,
        uint256[] calldata _tokenIDs
    ) private returns (uint256 rewardAmount) {
        uint160 _architectPerShareGrowthX64 = architectPerShareGrowthX64;

        uint256 tokenID;
        uint256 amount;
        for (uint256 i; i < _tokenIDs.length; ++i) {
            tokenID = _tokenIDs[i];

            amount = (_architectPerShareGrowthX64 - architectPerShareGrowthX64s[tokenID]) >> 64;
            architectPerShareGrowthX64s[tokenID] = _architectPerShareGrowthX64;

            rewardAmount += amount;

            emit ArchitectCollected(_receiver, tokenID, amount);
        }

        _transferOutAndUpdateFeeBalance(_receiver, rewardAmount);
    }

    function _allocateFee(uint256 _amount) private pure returns (uint256 equFeeAmount, uint256 architectFeeAmount) {
        unchecked {
            equFeeAmount = _amount >> 1;
            architectFeeAmount = _amount - equFeeAmount;
        }
    }

    function _validateStakeInfo(uint256 _id, uint64 _lockupStartTime, uint16 _period) private view {
        if (_lockupStartTime == 0) revert InvalidStakeID(_id);

        if (!_isInWithdrawalPeriod(_lockupStartTime, _period)) revert NotYetReachedTheUnlockingTime(_id);
    }

    function _isInWithdrawalPeriod(uint256 _lockupStartTime, uint256 _period) private view returns (bool isIn) {
        uint256 currentTime = block.timestamp;
        unchecked {
            isIn =
                _lockupStartTime + (_period * 1 days) < currentTime &&
                (currentTime - _lockupStartTime) % (_period * 1 days) <= uint256(withdrawalPeriod) * 1 days;
        }
    }

    function _calculateEQUAmount(uint256 _id) private view returns (int256 amount) {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = v3PositionManager.positions(_id);

        if (isToken0) _validateTokenPair(token0, token1);
        else _validateTokenPair(token1, token0);

        int24 tickSpacing = v3PoolFactory.feeAmountTickSpacing(fee);
        if (tickSpacing == 0) revert InvalidUniswapV3Fee(fee);

        _validateTicks(tickLower, tickUpper, tickSpacing);

        address pool = _computeV3PoolAddress(token0, token1, fee);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = IUniswapV3PoolMinimum(pool).slot0();

        int128 liquidityDelta = -int256(uint256(liquidity)).toInt128();
        if (tick < tickLower) {
            amount = isToken0
                ? -SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidityDelta
                )
                : int256(0);
        } else if (tick < tickUpper) {
            amount = isToken0
                ? -SqrtPriceMath.getAmount0Delta(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickUpper), liquidityDelta)
                : -SqrtPriceMath.getAmount1Delta(TickMath.getSqrtRatioAtTick(tickLower), sqrtPriceX96, liquidityDelta);
        } else {
            amount = isToken0
                ? int256(0)
                : -SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidityDelta
                );
        }
    }

    function _validateTokenPair(address _token0, address _token1) private view {
        if (address(EQU) != _token0 || address(WETH) != _token1) revert InvalidUniswapV3PositionNFT(_token0, _token1);
    }

    function _transferOutAndUpdateFeeBalance(address _receiver, uint256 _amount) private {
        feeBalance = uint96(feeBalance - _amount);
        feeToken.safeTransfer(_receiver, _amount);
    }

    function _computeV3PoolAddress(
        address _token0,
        address _token1,
        uint24 _fee
    ) internal view virtual returns (address pool) {
        pool = Create2.computeAddress(
            keccak256(abi.encode(_token0, _token1, _fee)),
            V3_POOL_INIT_HASH,
            address(v3PoolFactory)
        );
    }

    function _validateTicks(int24 tickLower, int24 tickUpper, int24 tickSpacing) private pure {
        unchecked {
            int24 maxTick = TickMath.MAX_TICK - (TickMath.MAX_TICK % tickSpacing);
            if (tickUpper < maxTick || tickLower > -maxTick)
                revert RequireFullRangePosition(tickLower, tickUpper, tickSpacing);
        }
    }
}
