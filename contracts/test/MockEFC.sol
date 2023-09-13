// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "../farming/interfaces/IRewardFarmCallback.sol";

contract MockEFC {
    uint256 private constant CONNECTOR_START_ID = 1000;
    uint256 private constant MEMBER_START_ID = 10000;
    uint256 private capPerConnectorCanMint;

    IRewardFarmCallback public callback;

    mapping(uint256 => address) private _tokenApprovals;
    mapping(bytes32 => uint256) public codeTokens;
    mapping(address => uint256) public refereeTokens;
    mapping(uint256 => uint256) public connectorTokenIds;

    function initialize(uint256 _capPerConnectorCanMint, IRewardFarmCallback _callback) external {
        capPerConnectorCanMint = _capPerConnectorCanMint;
        callback = _callback;
    }

    function setOwner(uint256 tokenId, address owner) external {
        _tokenApprovals[tokenId] = owner;
    }

    function setRefereeTokens(address referee, uint256 tokenId) external {
        refereeTokens[referee] = tokenId;
    }

    function referrerTokens(address referee) external view returns (uint256 _memberTokenId, uint256 _connectorTokenId) {
        _memberTokenId = refereeTokens[referee];
        if (_memberTokenId == 0) {
            return (0, 0);
        }
        return (_memberTokenId, _getConnectorId(_memberTokenId));
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        return _tokenApprovals[tokenId];
    }

    function registerCode(uint256 tokenId, bytes32 code) external {
        codeTokens[code] = tokenId;
    }

    function bindCode(bytes32 code) external {
        uint256 tokenIdAfter = codeTokens[code];
        address referee = msg.sender;
        uint256 tokenIdBefore = refereeTokens[referee];
        refereeTokens[referee] = tokenIdAfter;
        callback.onChangeReferralToken(
            referee,
            tokenIdBefore,
            connectorTokenIds[tokenIdBefore],
            tokenIdAfter,
            connectorTokenIds[tokenIdAfter]
        );
    }

    function bindConnectorTokenId(uint256 tokenId, uint256 connectorTokenId) external {
        connectorTokenIds[tokenId] = connectorTokenId;
    }

    function _getConnectorId(uint256 _memberId) private view returns (uint256) {
        unchecked {
            return CONNECTOR_START_ID + (_memberId - MEMBER_START_ID) / capPerConnectorCanMint;
        }
    }
}
