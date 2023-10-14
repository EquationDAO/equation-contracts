// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/governance/utils/Votes.sol";

abstract contract ERC721WeightedVotes is ERC721, Votes {
    mapping(address => uint256) private _votingUnitsBalance;

    function _weightOfToken(uint256 tokenId) internal view virtual returns (uint256 weight);

    function _getVotingUnits(address account) internal view override returns (uint256) {
        return _votingUnitsBalance[account];
    }

    function _transferVotingUnits(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0)) _votingUnitsBalance[from] = _votingUnitsBalance[from] - amount;
        if (to != address(0)) _votingUnitsBalance[to] = _votingUnitsBalance[to] + amount;

        super._transferVotingUnits(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        assert(batchSize == 1);
        _transferVotingUnits(from, to, _weightOfToken(firstTokenId));

        super._afterTokenTransfer(from, to, firstTokenId, batchSize);
    }
}
