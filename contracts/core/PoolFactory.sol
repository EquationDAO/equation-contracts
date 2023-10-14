// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./Configurable.sol";
import "./interfaces/IPoolFactory.sol";
import "../governance/Governable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract PoolFactory is IPoolFactory, Configurable, AccessControl {
    bytes public creationCode;
    bytes32 public creationCodeHash;

    IEFC public immutable EFC;
    Router public immutable router;
    IFeeDistributor public immutable feeDistributor;
    IRewardFarmCallback public immutable callback;
    IPriceFeed public priceFeed;

    /// @inheritdoc IPoolFactory
    mapping(IERC20 => IPool) public override pools;
    mapping(IPool => bool) private createdPools;

    IERC20 private token;

    constructor(
        IERC20 _usd,
        IEFC _efc,
        Router _router,
        IPriceFeed _priceFeed,
        IFeeDistributor _feeDistributor,
        IRewardFarmCallback _callback
    ) Configurable(_usd) {
        (EFC, router, priceFeed, feeDistributor, callback) = (_efc, _router, _priceFeed, _feeDistributor, _callback);
    }

    /// @notice Concatenates the creation code of the pool
    /// @dev Due to the contract size limit, it is not possible to retrieve the creation code of the contract through
    /// `type(Pool).creationCode`. Therefore, this function needs to be called multiple times to concatenate the
    /// creation code of the contract
    /// @param _lastCreationCodePart Indicates whether it is the last part of the creation code for the Pool contract
    /// @param _creationCodePart A part of the creation code for the Pool contract
    function concatPoolCreationCode(bool _lastCreationCodePart, bytes calldata _creationCodePart) external onlyGov {
        require(creationCodeHash == bytes32(0));

        creationCode = bytes.concat(creationCode, _creationCodePart);
        if (_lastCreationCodePart) creationCodeHash = keccak256(creationCode);
    }

    /// @notice Set the price feed contract
    function setPriceFeed(IPriceFeed _priceFeed) external onlyGov {
        priceFeed = _priceFeed;
    }

    /// @inheritdoc IPoolFactory
    function deployParameters()
        external
        view
        override
        returns (
            IERC20 _token,
            IERC20 _usd,
            Router _router,
            IFeeDistributor _feeDistributor,
            IEFC _EFC,
            IRewardFarmCallback _callback
        )
    {
        return (token, usd, router, feeDistributor, EFC, callback);
    }

    /// @inheritdoc IPoolFactory
    function isPool(address _pool) external view override returns (bool) {
        return createdPools[IPool(_pool)];
    }

    /// @inheritdoc IPoolFactory
    function createPool(IERC20 _token) external override nonReentrant returns (IPool pool) {
        _onlyGov();

        if (pools[_token] != IPool(address(0))) revert PoolAlreadyExists(pools[_token]);

        if (!_isEnabledToken(_token)) revert TokenNotEnabled(_token);

        pool = _deploy(_token);
        pools[_token] = pool;
        createdPools[pool] = true;

        emit PoolCreated(pool, _token, usd);
    }

    /// @inheritdoc IPoolFactory
    function gov() public view override(IPoolFactory, Governable) returns (address) {
        return super.gov();
    }

    function _deploy(IERC20 _token) internal returns (IPool _pool) {
        if (creationCodeHash == bytes32(0)) revert NotInitialized();

        token = _token;

        _pool = IPool(Create2.deploy(0, keccak256(abi.encode(_token, usd)), creationCode));

        delete token;
    }

    /// @inheritdoc Governable
    function _changeGov(address _newGov) internal override(Governable) {
        super._revokeRole(DEFAULT_ADMIN_ROLE, super.gov());
        super._changeGov(_newGov);
        super._grantRole(DEFAULT_ADMIN_ROLE, _newGov);
    }

    /// @inheritdoc Configurable
    function afterTokenConfigChanged(IERC20 _token) internal override {
        IPool pool = pools[_token];
        if (address(pool) != address(0)) pool.onChangeTokenConfig();
    }
}
