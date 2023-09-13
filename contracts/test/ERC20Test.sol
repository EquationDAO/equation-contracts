// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract ERC20Test is ERC20, ERC20Votes {
    uint8 private myDecimals;

    receive() external payable {}

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        myDecimals = _decimals;

        _mint(_msgSender(), _initialSupply);
    }

    function decimals() public view override returns (uint8) {
        return myDecimals;
    }

    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _burn(address account, uint256 amount) internal virtual override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }

    function _mint(address account, uint256 amount) internal virtual override(ERC20, ERC20Votes) {
        super._mint(account, amount);
    }
}
