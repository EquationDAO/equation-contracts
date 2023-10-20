// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title Interface for the IEFC contract
/// @notice This contract is used to register referral codes and bind them to users
interface IEFC is IERC721 {
    /// @notice Emitted when a referral code is registered
    /// @param referrer The address of the user who registered the code
    /// @param code The code to register
    /// @param tokenId The id of the token to register the code for
    event CodeRegistered(address indexed referrer, uint256 indexed tokenId, string code);

    /// @notice Emitted when a referral code is bound
    /// @param referee The address of the user who bound the code
    /// @param code The code to bind
    /// @param tokenIdBefore The id of the token before the code is bound
    /// @param tokenIdAfter The id of the token after the code is bound
    event CodeBound(address indexed referee, string code, uint256 tokenIdBefore, uint256 tokenIdAfter);

    /// @notice Param cap is too large
    /// @param capArchitect Cap of architect can be minted
    /// @param capConnector Cap of connector can be minted
    error CapTooLarge(uint256 capArchitect, uint256 capConnector);

    /// @notice Token is not member
    /// @param tokenId The tokenId
    error NotMemberToken(uint256 tokenId);

    /// @notice Token is not connector
    /// @param tokenId The tokenId
    error NotConnectorToken(uint256 tokenId);

    /// @notice Cap exceeded
    /// @param cap The cap
    error CapExceeded(uint256 cap);

    /// @notice Invalid code
    error InvalidCode();

    /// @notice Caller is not the owner
    /// @param owner The owner
    error CallerIsNotOwner(address owner);

    /// @notice Code is already registered
    /// @param code The code
    error CodeAlreadyRegistered(string code);

    /// @notice Code is not registered
    /// @param code The code
    error CodeNotRegistered(string code);

    /// @notice Set the base URI of nft assets
    /// @param baseURI Base URI for NFTs
    function setBaseURI(string calldata baseURI) external;

    /// @notice Get the token for a code
    /// @param code The code to get the token for
    /// @return tokenId The id of the token for the code
    function codeTokens(string calldata code) external view returns (uint256 tokenId);

    /// @notice Get the member and connector token id who referred the referee
    /// @param referee The address of the referee
    /// @return memberTokenId The token id of the member
    /// @return connectorTokenId The token id of the connector
    function referrerTokens(address referee) external view returns (uint256 memberTokenId, uint256 connectorTokenId);

    /// @notice Register a referral code for the referrer
    /// @param tokenId The id of the token to register the code for
    /// @param code The code to register
    function registerCode(uint256 tokenId, string calldata code) external;

    /// @notice Bind a referral code for the referee
    /// @param code The code to bind
    function bindCode(string calldata code) external;
}
