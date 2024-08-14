// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IParlayCoreSimple.sol";

/// @title ParlayUserTokenAntiWhale
/// @notice This contract implements an ERC20 token with anti-whale feature.
contract AntiWhaleParlayToken is ERC20 {
  /// @notice Indicates if the anti-whale feature is enabled
  bool public limitsEnabled = true;

  /// @notice The address of the factory that deployed this contract
  address public immutable parlayCoreSimple;

  /// @notice The maximum balance a wallet can hold when anti-whale is enabled
  uint256 public maxWalletBalance;

  address public immutable uniswapV2Pair;

  /// @notice Constructor to initialize the token with a name, symbol, total supply, and initial max wallet balance
  /// @param _name The name of the token
  /// @param _symbol The symbol of the token
  /// @param _totalSupply The total supply of the token
  /// @param _initialMaxWalletBalance The initial maximum wallet balance
  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _totalSupply,
    uint256 _initialMaxWalletBalance
  ) ERC20(_name, _symbol) {
    parlayCoreSimple = msg.sender;
    maxWalletBalance = _initialMaxWalletBalance;
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

      if (to != address(0) && to != parlayCoreSimple) {
        require(
          balanceOf(to) + amount <= maxWalletBalance,
          "Transfer exceeds max wallet balance"
        );
      }
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