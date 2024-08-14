// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IParlayCoreSimple.sol";

/// @title ParlayUserToken
/// @notice This contract implements an ERC20 token with permit functionality.
contract BasicParlayToken is ERC20 {
  /// @notice Indicates if the anti-whale feature is enabled
  bool public limitsEnabled = true;

  /// @notice The address of the factory that deployed this contract
  address public immutable parlayCoreSimple;

  address public immutable uniswapV2Pair;

  /// @notice Constructor to initialize the token with a name and symbol.
  /// @param _name The name of the token.
  /// @param _symbol The symbol of the token.
  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _totalSupply
  ) ERC20(_name, _symbol) {
    parlayCoreSimple = msg.sender;
    uniswapV2Pair = IParlayCoreSimple(parlayCoreSimple).getPairAddress(
      address(this)
    );
    _mint(msg.sender, _totalSupply);
  }

  /// @notice Internal function to update balances and enforce anti-whale rules
  /// @param from The address sending the tokens
  /// @param to The address receiving the tokens
  /// @param amount The amount of tokens being transferred
  function _update(address from, address to, uint256 amount) internal override {
    super._update(from, to, amount);

    if (limitsEnabled) {
      require(
        to != uniswapV2Pair,
        "Transfers to Uniswap V2 pair are not allowed when limits are enabled"
      );
    }
  }

  /// @notice Function to remove limits at bonding.
  /// @dev Only the core address can call this function.
  function removeLimits() external {
    require(
      msg.sender == parlayCoreSimple,
      "Only factory can remove anti-whale"
    );
    limitsEnabled = false;
  }
}