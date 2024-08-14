// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./token/BasicParlayToken.sol";
import "./token/AntiWhaleParlayToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IUniswapV2Router02.sol";


interface IParlayToken {
  function removeLimits() external;
}

/// @title ParlayCoreSimple
/// @author Parlay Labs
contract ParlayCoreSimple is Ownable, EIP712, ReentrancyGuard {
  using ECDSA for bytes32;

  struct Token {
    uint256 etherBalance;
    uint256 virtualEtherBalance;
    uint256 tokensForUniswapBalance;
    uint256 tokensForBondingCurveBalance;
  }

  struct Lock {
    uint256 amount;
    address creator;
  }

  struct CreateTokenRequest {
    string name;
    string symbol;
    uint256 deadline;
    address creator;
    uint256 creatorSignatureNonce;
    uint256 etherFee;
    uint256 etherBuy;
    uint256 initialMaxWalletBalance;
    bool isDevLockup;
  }

  mapping(address => Token) public tokens;
  mapping(address => Lock) public creatorLocks;
  mapping(address => uint256) public signatureNonces;

  bytes32 public CREATE_TYPEHASH;
  bytes32 public INIT_CODE_PAIR_HASH;

  address public immutable uniswapV2Router02;
  address public immutable burnAddress;
  address public signer;

  uint256 public etherFeeBalance;
  uint256 public tradingFeeBasisPoints;
  uint256 public initialVirtualEtherBalance;
  uint256 public initialTokensForUniswapBalance;
  uint256 public initialTokensForBondingCurveBalance;

  bool public tradingEnabled;
  bool public tokenCreationEnabled;

  event TradeExecuted(
    address indexed token,
    address indexed user,
    uint256 etherAmountIn,
    uint256 etherAmountOut,
    uint256 tokenAmountIn,
    uint256 tokenAmountOut,
    uint256 timestamp,
    uint256 etherFeeAmount
  );
  event TokenCreated(
    bytes32 indexed digest,
    address indexed token,
    uint256 indexed timestamp,
    uint256 totalSupply,
    uint256 initialVirtualEtherBalance,
    uint256 initialTokensForUniswapBalance,
    uint256 initialTokensForBondingCurveBalance,
    address uniswapV2Pair
  );
  event FeesWithdrawn(uint256 indexed amount);
  event SignerChanged(address indexed oldSigner, address indexed newSigner);
  event TokenInitializerChanged(
    uint256 indexed initialVirtualEtherBalance,
    uint256 indexed initialTokensForUniswapBalance,
    uint256 indexed initialTokensForBondingCurveBalance
  );
  event CreatorTokensLocked(
    address indexed tokenAddress,
    address indexed creator,
    uint256 amount
  );
  event CreatorTokensUnlocked(
    address indexed tokenAddress,
    address indexed creator,
    uint256 amount
  );
  event TokenSeeded(address indexed tokenAddress);
  event TradingEnabledToggled(bool newState);
  event TokenCreationEnabledToggled(bool newState);
  event EtherFeeCollected(uint256 etherFeeAmount);

  /// @notice Constructor to initialize the ParlayCoreSimple contract
  /// @param _signer The address of the signer
  /// @param _initialVirtualEtherBalance The initial virtual ether balance
  /// @param _initialTokensForUniswapBalance The initial tokens for Uniswap balance
  /// @param _initialTokensForBondingCurveBalance The initial tokens for bonding curve balance
  /// @param _uniswapV2Router02 The address of the Uniswap V2 Router
  /// @param _tradingFeeBasisPoints The trading fee in basis points
  constructor(
    address _signer,
    uint256 _initialVirtualEtherBalance,
    uint256 _initialTokensForUniswapBalance,
    uint256 _initialTokensForBondingCurveBalance,
    address _uniswapV2Router02,
    uint256 _tradingFeeBasisPoints,
    bytes32 _createTypeHash,
    bytes32 _initCodePairHash
  ) Ownable(msg.sender) EIP712("ParlayCoreSimple", "1") {
    signer = _signer;
    initialVirtualEtherBalance = _initialVirtualEtherBalance;
    initialTokensForUniswapBalance = _initialTokensForUniswapBalance;
    initialTokensForBondingCurveBalance = _initialTokensForBondingCurveBalance;
    uniswapV2Router02 = _uniswapV2Router02;
    tradingFeeBasisPoints = _tradingFeeBasisPoints;
    tradingEnabled = true;
    tokenCreationEnabled = true;
    CREATE_TYPEHASH = _createTypeHash;
    INIT_CODE_PAIR_HASH = _initCodePairHash;
    burnAddress = address(0);
  }

  /// @notice Creates a new token
  /// @param name The name of the token
  /// @param symbol The symbol of the token
  /// @param deadline The deadline for the token creation
  /// @param etherFee The ether fee for the token creation
  /// @param etherBuy The ether amount to buy tokens
  /// @param initialMaxWalletBalance The initial maximum wallet balance
  /// @param isDevLockup Boolean indicating if the token has dev lockup feature
  /// @param v The recovery id of the signature
  /// @param r The r value of the signature
  /// @param s The s value of the signature
  function createToken(
    string calldata name,
    string calldata symbol,
    uint256 deadline,
    uint256 etherFee,
    uint256 etherBuy,
    uint256 initialMaxWalletBalance,
    bool isDevLockup,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external payable nonReentrant {
    require(tokenCreationEnabled, "ParlayCore: token creation is disabled");
    require(deadline >= block.timestamp, "ParlayCore: deadline has passed");
    require(
      etherFee + etherBuy == msg.value,
      "ParlayCore: invalid ether fee and buy"
    );

    if (isDevLockup) {
      require(etherBuy > 0, "ParlayCore: must buy tokens for dev lockup");
    }

    uint256 creatorSignatureNonce = signatureNonces[msg.sender]++;

    bytes32 typeDomainHash = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 eip712DomainHash = keccak256(abi.encode(typeDomainHash, keccak256(bytes("ParlayCoreSimple")), keccak256(bytes("1")), block.chainid, address(this)));
    bytes32 typeStructHash = keccak256(
                abi.encode(
                    CREATE_TYPEHASH,
                    keccak256(abi.encodePacked(name)),
                    keccak256(abi.encodePacked(symbol)),
                    deadline,
                    msg.sender,
                    creatorSignatureNonce,
                    etherFee,
                    etherBuy,
                    initialMaxWalletBalance,
                    isDevLockup
                )
            );
    bytes32 hash = keccak256(abi.encodePacked("\x19\x01", eip712DomainHash, typeStructHash));

    address recoveredSigner = ECDSA.recover(hash, v, r, s);
    require(recoveredSigner == signer, "ParlayCore: invalid signature");

    uint256 tokenTotalSupply = initialTokensForUniswapBalance +
      initialTokensForBondingCurveBalance;

    address tokenAddress;
    if (initialMaxWalletBalance > 0) {
      tokenAddress = address(
        new AntiWhaleParlayToken(
          name,
          symbol,
          tokenTotalSupply,
          initialMaxWalletBalance
        )
      );
    } else {
      tokenAddress = address(
        new BasicParlayToken(name, symbol, tokenTotalSupply)
      );
    }

    tokens[tokenAddress] = Token({
      etherBalance: initialVirtualEtherBalance,
      virtualEtherBalance: initialVirtualEtherBalance,
      tokensForUniswapBalance: initialTokensForUniswapBalance,
      tokensForBondingCurveBalance: initialTokensForBondingCurveBalance
    });

    collectEtherFee(etherFee);

    address uniswapV2Pair = IParlayCoreSimple(address(this)).getPairAddress(
      tokenAddress
    );

    emit TokenCreated(
      hash,
      tokenAddress,
      block.timestamp,
      tokenTotalSupply,
      initialVirtualEtherBalance,
      initialTokensForUniswapBalance,
      initialTokensForBondingCurveBalance,
      uniswapV2Pair
    );

    if (etherBuy > 0) {
      address buyReceiver = isDevLockup ? address(this) : msg.sender;
      uint256 tokensBought = _buyTokens(tokenAddress, buyReceiver, etherBuy);
      if (isDevLockup) {
        creatorLocks[tokenAddress] = Lock({
          amount: tokensBought,
          creator: msg.sender
        });
        emit CreatorTokensLocked(tokenAddress, msg.sender, tokensBought);
      }
    }
  }

  /// @notice Internal function to buy tokens
  /// @param tokenAddress The address of the token
  /// @param to The address to send the tokens to
  /// @param etherAmountForSwap The amount of ether to swap for tokens
  function _buyTokens(
    address tokenAddress,
    address to,
    uint256 etherAmountForSwap
  ) internal returns (uint256) {
    Token storage token = tokens[tokenAddress];
    require(token.tokensForBondingCurveBalance > 0, "Token not available");

    uint256 fee = (etherAmountForSwap * tradingFeeBasisPoints) / 10000;
    uint256 amountInAfterFee = etherAmountForSwap - fee;

    uint totalTokens = token.tokensForBondingCurveBalance +
      token.tokensForUniswapBalance;
    uint amountOut = getAmountOut(
      amountInAfterFee,
      token.etherBalance,
      totalTokens
    );
    require(amountOut >= 0, "Insufficient output amount");
    require(
      amountOut <= token.tokensForBondingCurveBalance,
      "Bonding curve empty"
    );

    token.etherBalance += amountInAfterFee;
    token.tokensForBondingCurveBalance -= amountOut;
    collectEtherFee(fee);

    IERC20(tokenAddress).transfer(to, amountOut);

    emit TradeExecuted(
      tokenAddress,
      to,
      etherAmountForSwap,
      0,
      0,
      amountOut,
      block.timestamp,
      fee
    );

    return amountOut;
  }

  /// @notice Swaps exact ETH for tokens
  /// @param tokenAddress The address of the token
  /// @param amountOutMin The minimum amount of tokens to receive
  function swapExactETHForTokens(
    address tokenAddress,
    uint amountOutMin
  ) external payable nonReentrant {
    require(tradingEnabled, "ParlayCore: trading is disabled");
    Token storage token = tokens[tokenAddress];
    require(token.tokensForBondingCurveBalance > 0, "Token not available");

    uint256 fee = (msg.value * tradingFeeBasisPoints) / 10000;
    uint256 amountInAfterFee = msg.value - fee;

    uint totalTokens = token.tokensForBondingCurveBalance +
      token.tokensForUniswapBalance;
    uint amountOut = getAmountOut(
      amountInAfterFee,
      token.etherBalance,
      totalTokens
    );
    require(amountOut >= amountOutMin, "Insufficient output amount");
    require(
      amountOut <= token.tokensForBondingCurveBalance,
      "Bonding curve empty"
    );

    token.etherBalance += amountInAfterFee;
    token.tokensForBondingCurveBalance -= amountOut;
    collectEtherFee(fee);

    IERC20(tokenAddress).transfer(msg.sender, amountOut);

    emit TradeExecuted(
      tokenAddress,
      msg.sender,
      msg.value,
      0,
      0,
      amountOut,
      block.timestamp,
      fee
    );
  }

  /// @notice Swaps exact tokens for ETH
  /// @param tokenAddress The address of the token
  /// @param amountIn The amount of tokens to swap
  /// @param amountOutMin The minimum amount of ETH to receive
  function swapExactTokensForETH(
    address tokenAddress,
    uint amountIn,
    uint amountOutMin
  ) external nonReentrant {
    require(tradingEnabled, "ParlayCore: trading is disabled");
    Token storage token = tokens[tokenAddress];
    require(token.tokensForBondingCurveBalance > 0, "Token not available");

    uint totalTokens = token.tokensForBondingCurveBalance +
      token.tokensForUniswapBalance;
    uint amountOut = getAmountOut(amountIn, totalTokens, token.etherBalance);
    require(amountOut >= amountOutMin, "Insufficient output amount");

    uint256 fee = (amountOut * tradingFeeBasisPoints) / 10000;
    uint256 amountOutAfterFee = amountOut - fee;

    require(
      amountOutAfterFee >= amountOutMin,
      "Insufficient output amount after fee"
    );

    require(
      token.etherBalance - amountOutAfterFee >= token.virtualEtherBalance,
      "Insufficient ether balance"
    );

    IERC20(tokenAddress).transferFrom(msg.sender, address(this), amountIn);

    token.etherBalance -= amountOut;
    token.tokensForBondingCurveBalance += amountIn;
    collectEtherFee(fee);

    (bool success, ) = payable(msg.sender).call{value: amountOutAfterFee}("");
    require(success, "Transfer failed");

    emit TradeExecuted(
      tokenAddress,
      msg.sender,
      0,
      amountOutAfterFee,
      amountIn,
      0,
      block.timestamp,
      fee
    );
  }

  /// @notice Calculates the amount of output tokens for a given input amount
  /// @param amountIn The amount of input tokens
  /// @param reserveIn The reserve of input tokens
  /// @param reserveOut The reserve of output tokens
  /// @return amountOut The amount of output tokens
  function getAmountOut(
    uint amountIn,
    uint reserveIn,
    uint reserveOut
  ) public pure returns (uint amountOut) {
    require(amountIn > 0, "Insufficient input amount");
    require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
    uint numerator = amountIn * reserveOut;
    uint denominator = reserveIn + amountIn;
    amountOut = numerator / denominator;
  }

  /// @notice Seeds liquidity for a token
  /// @param tokenAddress The address of the token
  function seedLiquidity(address tokenAddress) external nonReentrant {
    Token storage token = tokens[tokenAddress];
    require(
      token.tokensForBondingCurveBalance <= 1e18,
      "Tokens are still available on the bondive curve"
    );
    IParlayToken(tokenAddress).removeLimits();
    uint256 etherAmount = token.etherBalance - token.virtualEtherBalance;
    uint256 tokenAmount = token.tokensForUniswapBalance +
      token.tokensForBondingCurveBalance;

    IERC20(tokenAddress).approve(uniswapV2Router02, tokenAmount);

    IUniswapV2Router02(uniswapV2Router02).addLiquidityETH{value: etherAmount}(
      tokenAddress,
      tokenAmount,
      0,
      0,
      burnAddress,
      block.timestamp
    );
    if (creatorLocks[tokenAddress].amount > 0) {
      IERC20(tokenAddress).transfer(
        creatorLocks[tokenAddress].creator,
        creatorLocks[tokenAddress].amount
      );
      emit CreatorTokensUnlocked(
        tokenAddress,
        creatorLocks[tokenAddress].creator,
        creatorLocks[tokenAddress].amount
      );
      delete creatorLocks[tokenAddress];
    }
    emit TokenSeeded(tokenAddress);
    delete tokens[tokenAddress];
  }

  function collectEtherFee(uint256 amount) internal {
    etherFeeBalance += amount;
    emit EtherFeeCollected(amount);
  }

  //////////////////////
  /////ADMIN///////////
  //////////////////////

  /// @notice Withdraws the ether fee balance
  function withdrawEtherFee() external onlyOwner {
    payable(msg.sender).transfer(etherFeeBalance);
    etherFeeBalance = 0;
    emit FeesWithdrawn(etherFeeBalance);
  }

  /// @notice Sets the signer address
  /// @param _signer The new signer address
  function setSigner(address _signer) external onlyOwner {
    signer = _signer;
  }

  /// @notice Sets the token initializer values
  /// @param _initialVirtualEtherBalance The initial virtual ether balance
  /// @param _initialTokensForUniswapBalance The initial tokens for Uniswap balance
  /// @param _initialTokensForBondingCurveBalance The initial tokens for bonding curve balance
  function setTokenInitializer(
    uint256 _initialVirtualEtherBalance,
    uint256 _initialTokensForUniswapBalance,
    uint256 _initialTokensForBondingCurveBalance
  ) external onlyOwner {
    initialVirtualEtherBalance = _initialVirtualEtherBalance;
    initialTokensForUniswapBalance = _initialTokensForUniswapBalance;
    initialTokensForBondingCurveBalance = _initialTokensForBondingCurveBalance;
    emit TokenInitializerChanged(
      initialVirtualEtherBalance,
      initialTokensForUniswapBalance,
      initialTokensForBondingCurveBalance
    );
  }

  /// @notice Toggles the trading enabled state
  /// @dev This function can only be called by the owner
  function flipTradingEnabled() external onlyOwner {
    tradingEnabled = !tradingEnabled;
    emit TradingEnabledToggled(tradingEnabled);
  }

  /// @notice Toggles the token creation enabled state
  /// @dev This function can only be called by the owner
  function flipTokenCreationEnabled() external onlyOwner {
    tokenCreationEnabled = !tokenCreationEnabled;
    emit TokenCreationEnabledToggled(tokenCreationEnabled);
  }

  /// @notice Sets the trading fee basis points
  /// @param _tradingFeeBasisPoints The new trading fee basis points
  function setTradingFeeBasisPoints(
    uint256 _tradingFeeBasisPoints
  ) external onlyOwner {
    require(
      _tradingFeeBasisPoints <= 10000,
      "Trading fee basis points must be less than or equal to 10000(100%)"
    );
    tradingFeeBasisPoints = _tradingFeeBasisPoints;
  }

  /// @notice Returns the domain separator
  /// @return domainSeparator The domain separator
  function DOMAIN_SEPARATOR()
    external
    view
    virtual
    returns (bytes32 domainSeparator)
  {
    return _domainSeparatorV4();
  }

  /// @notice Returns the struct hash for a create token request
  /// @param _createTokenRequest The create token request
  /// @return structHash The struct hash
  function getCreateTokenRequestStructHash(
    CreateTokenRequest memory _createTokenRequest
  ) internal view returns (bytes32 structHash) {
    return
      keccak256(
        abi.encode(
          CREATE_TYPEHASH,
          keccak256(bytes(_createTokenRequest.name)),
          keccak256(bytes(_createTokenRequest.symbol)),
          _createTokenRequest.deadline,
          _createTokenRequest.creator,
          _createTokenRequest.creatorSignatureNonce,
          _createTokenRequest.etherFee,
          _createTokenRequest.etherBuy,
          _createTokenRequest.initialMaxWalletBalance,
          _createTokenRequest.isDevLockup
        )
      );
  }

  /// @notice Returns the typed data hash for a create token request
  /// @param _createTokenRequest The create token request
  /// @return typedDataHash The typed data hash
  function getCreateTokenRequestTypedDataHash(
    CreateTokenRequest memory _createTokenRequest
  ) public view returns (bytes32 typedDataHash) {
    return
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          _domainSeparatorV4(),
          getCreateTokenRequestStructHash(_createTokenRequest)
        )
      );
  }

  /// @notice Returns the deterministic Uniswap V2 pair address for a token.
  /// @param tokenA The address of the first token
  /// @return pair The address of the Uniswap V2 pair
  function getPairAddress(address tokenA) public view returns (address pair) {
    address tokenB = IUniswapV2Router02(uniswapV2Router02).WETH();
    (address token0, address token1) = tokenA < tokenB
      ? (tokenA, tokenB)
      : (tokenB, tokenA);
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                hex"ff",
                IUniswapV2Router02(uniswapV2Router02).factory(),
                keccak256(abi.encodePacked(token0, token1)),
                INIT_CODE_PAIR_HASH
              )
            )
          )
        )
      ); 
  }
}