// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./MultiMinter.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract veEQU is ERC20, ERC20Permit, ERC20Votes, MultiMinter {
    error Unsupported();

    constructor() ERC20("veEQU", "veEQU") ERC20Permit("veEQU") {}

    function mint(address account, uint256 amount) public onlyMinter {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyMinter {
        _burn(account, amount);
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert Unsupported();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert Unsupported();
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}
