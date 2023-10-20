// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./ERC721WeightedVotes.sol";
import "./interfaces/IEFC.sol";
import "../libraries/ReentrancyGuard.sol";
import "../governance/Governable.sol";
import "../farming/interfaces/IRewardFarmCallback.sol";
import "../staking/interfaces/IFeeDistributorCallback.sol";
import "@openzeppelin/contracts/governance/utils/Votes.sol";

contract EFC is IEFC, ERC721WeightedVotes, Governable, ReentrancyGuard {
    uint256 private constant ARCHITECT_START_ID = 1;
    uint256 private constant CONNECTOR_START_ID = 1000;
    uint256 private constant MEMBER_START_ID = 10000;

    /// @dev Maximum number of architect tokens
    uint256 private immutable capArchitect;
    /// @dev Maximum number of connector tokens
    uint256 private immutable capConnector;
    /// @dev Maximum number of member tokens that a connector can mint
    uint256 private immutable capPerConnectorCanMint;

    /// @inheritdoc IEFC
    mapping(string => uint256) public override codeTokens;

    IRewardFarmCallback public immutable rewardFarmCallback;
    IFeeDistributorCallback public immutable feeDistributorCallback;
    mapping(address => uint256) public refereeTokens;

    /// @dev Number of architect tokens minted
    uint256 public architectMinted;
    /// @dev Number of connector tokens minted
    uint256 public connectorMinted;
    /// @dev Store number of member tokens that a connector minted
    mapping(uint256 => uint256) public memberMintedCounter;

    /// @notice Base URI for NFTs
    string public baseURI;

    modifier onlyConnectorOwner(uint256 connectorTokenId) {
        if (!_isConnector(connectorTokenId)) revert NotConnectorToken(connectorTokenId);
        if (_msgSender() != ownerOf(connectorTokenId)) revert CallerIsNotOwner(ownerOf(connectorTokenId));
        _;
    }

    constructor(
        uint256 _capArchitect,
        uint256 _capConnector,
        uint256 _capPerConnectorCanMint,
        IRewardFarmCallback _rewardFarmCallback,
        IFeeDistributorCallback _feeDistributorCallback
    ) ERC721("Equation Founders Club", "EFC") EIP712("EFC", "1.0") {
        if (
            ARCHITECT_START_ID + _capArchitect > CONNECTOR_START_ID ||
            CONNECTOR_START_ID + _capConnector > MEMBER_START_ID
        ) revert CapTooLarge(_capArchitect, _capConnector);

        (capArchitect, capConnector, capPerConnectorCanMint) = (_capArchitect, _capConnector, _capPerConnectorCanMint);
        (rewardFarmCallback, feeDistributorCallback) = (_rewardFarmCallback, _feeDistributorCallback);
    }

    /// @inheritdoc IEFC
    function setBaseURI(string calldata _URI) external override onlyGov {
        baseURI = _URI;
    }

    /// @inheritdoc ERC721
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function batchMintArchitect(address[] calldata _to) external onlyGov nonReentrant {
        uint256 architectMintedBefore = architectMinted;
        architectMinted = architectMintedBefore + _to.length;
        if (architectMinted > capArchitect) revert CapExceeded(capArchitect);

        uint256 mintStartId = ARCHITECT_START_ID + architectMintedBefore;
        for (uint256 i; i < _to.length; ++i) {
            uint256 tokenId = mintStartId + i;
            _safeMint(_to[i], tokenId);
            feeDistributorCallback.onMintArchitect(tokenId);
        }
    }

    function batchMintConnector(address[] calldata _to) external onlyGov nonReentrant {
        uint256 connectorMintedBefore = connectorMinted;
        connectorMinted = connectorMintedBefore + _to.length;
        if (connectorMinted > capConnector) revert CapExceeded(capConnector);

        _safeBatchMint(CONNECTOR_START_ID + connectorMintedBefore, _to);
    }

    function batchMintMember(
        uint256 _connectorTokenId,
        address[] calldata _to
    ) external onlyConnectorOwner(_connectorTokenId) nonReentrant {
        uint256 numOfMinted = memberMintedCounter[_connectorTokenId];
        if (numOfMinted + _to.length > capPerConnectorCanMint) revert CapExceeded(capPerConnectorCanMint);

        uint256 connectorStartId = (_connectorTokenId - CONNECTOR_START_ID) * capPerConnectorCanMint;
        uint256 mintStartId = MEMBER_START_ID + connectorStartId + numOfMinted;
        _safeBatchMint(mintStartId, _to);
        memberMintedCounter[_connectorTokenId] = numOfMinted + _to.length;
    }

    /// @inheritdoc IEFC
    function registerCode(uint256 _tokenId, string calldata _code) external override {
        if (!_isMember(_tokenId)) revert NotMemberToken(_tokenId);
        if (bytes(_code).length == 0) revert InvalidCode();
        address owner = ownerOf(_tokenId);
        if (owner != _msgSender()) revert CallerIsNotOwner(owner);
        if (codeTokens[_code] != 0) revert CodeAlreadyRegistered(_code);
        codeTokens[_code] = _tokenId;
        emit CodeRegistered(owner, _tokenId, _code);
    }

    /// @inheritdoc IEFC
    function bindCode(string calldata _code) external override {
        uint256 tokenIdAfter = codeTokens[_code];
        if (tokenIdAfter == 0) revert CodeNotRegistered(_code);
        address referee = _msgSender();
        uint256 tokenIdBefore = refereeTokens[referee];
        refereeTokens[referee] = tokenIdAfter;
        emit CodeBound(referee, _code, tokenIdBefore, tokenIdAfter);

        rewardFarmCallback.onChangeReferralToken(
            referee,
            tokenIdBefore,
            tokenIdBefore == 0 ? 0 : _getConnectorId(tokenIdBefore),
            tokenIdAfter,
            _getConnectorId(tokenIdAfter)
        );
    }

    /// @inheritdoc IEFC
    function referrerTokens(
        address referee
    ) external view override returns (uint256 _memberTokenId, uint256 _connectorTokenId) {
        _memberTokenId = refereeTokens[referee];
        return (_memberTokenId == 0) ? (0, 0) : (_memberTokenId, _getConnectorId(_memberTokenId));
    }

    function _weightOfToken(uint256 _tokenId) internal pure override returns (uint256) {
        return _isArchitect(_tokenId) ? 1 : 0;
    }

    function _safeBatchMint(uint256 _startID, address[] calldata _to) private {
        for (uint256 i; i < _to.length; ++i) _safeMint(_to[i], _startID + i);
    }

    function _isArchitect(uint256 _tokenId) private pure returns (bool) {
        return _tokenId != 0 && _tokenId < CONNECTOR_START_ID;
    }

    function _isConnector(uint256 _tokenId) private pure returns (bool) {
        return _tokenId >= CONNECTOR_START_ID && _tokenId < MEMBER_START_ID;
    }

    function _isMember(uint256 _tokenId) private pure returns (bool) {
        return _tokenId >= MEMBER_START_ID;
    }

    function _getConnectorId(uint256 _memberId) private view returns (uint256) {
        // prettier-ignore
        unchecked { return CONNECTOR_START_ID + (_memberId - MEMBER_START_ID) / capPerConnectorCanMint; }
    }
}
