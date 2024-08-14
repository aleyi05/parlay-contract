const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers"); 
const { ethers } = require("hardhat");
const { expect } = require("chai");
const web3 = require('web3');
const ethSigUtil = require("eth-sig-util");


describe("test contract", function() {
    async function deployTestFixture() {

        const [owner] = await ethers.getSigners();
        const createTypeHash = ethers.keccak256(ethers.toUtf8Bytes("createToken(string name,string symbol,uint256 deadline,uint256 etherFee,uint256 etherBuy,uint256 initialMaxWalletBalance,bool isDevLockup)"));
        const initCodePairHash = ethers.keccak256(ethers.toUtf8Bytes("InitCodePair"));
    
        const signerAddress = owner.address; // Replace with the actual signer address
        const initialVirtualEtherBalance = ethers.parseEther("0.5"); // Example value, adjust as needed
        const initialTokensForUniswapBalance = ethers.parseEther("1000"); // Example value, adjust as needed
        const initialTokensForBondingCurveBalance = ethers.parseEther("1000"); // Example value, adjust as needed
        const uniswapV2Router02Address = "0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008"; // Replace with the actual Uniswap V2 Router address
        const tradingFeeBasisPoints = 300; // Example value (5%)
        
        const ParlayCoreSimple = await ethers.getContractFactory("ParlayCoreSimple");
        const parlayCoreSimple = await ParlayCoreSimple.deploy(
            createTypeHash,
            initCodePairHash,
            signerAddress,
            initialVirtualEtherBalance,
            initialTokensForUniswapBalance,
            initialTokensForBondingCurveBalance,
            uniswapV2Router02Address,
            tradingFeeBasisPoints,
        )
        
        await parlayCoreSimple.waitForDeployment();
        const parlayCoreSimpleAddress = await parlayCoreSimple.getAddress();
        console.log("ParlayCoreSimple Contract is deployed at", parlayCoreSimpleAddress);
            return { owner,parlayCoreSimple, parlayCoreSimpleAddress }
    };
    
    describe("Deployment", function() {
        it("Sign, Contract deploy, token deploy", async function() {
            
            const { owner,parlayCoreSimple, parlayCoreSimpleAddress} = await loadFixture(deployTestFixture);

            const provider = ethers.provider; // Get the Hardhat provider
            const network = await provider.getNetwork(); // Get network info
            console.log("Current chainId:", Number(network.chainId)); 

            const blockNumber = await provider.getBlockNumber();
            const block = await provider.getBlock(blockNumber);
            const timestamp = block.timestamp;

            const name = 'ParlayTestToken';
            const symbol = 'PTEST';
            const deadline = timestamp + 3600; // 1 hour from now
            const etherFee = ethers.utils.parseEther('0.1'); // 0.1
            const etherBuy = 0;
            const initialMaxWalletBalance = ethers.utils.parseEther('10000'); // 100 ether
            const isDevLockup = false;
            const sigNonce = await parlayContract.signatureNonces(owner);
            
            const eip712Message = {
              "domain": {
                "name": "ParlayCoreSimple",
                "version": "1",
                "chainId": chainId,
                "verifyingContract": process.env.parlayAddress,
              },
              "primaryType": "CreateTokenRequest",
              "types": {
                "EIP712Domain": [
                      { name: "name", type: "string" },
                      { name: "version", type: "string" },
                      { name: "chainId", type: "uint256" },
                      { name: "verifyingContract", type: "address" }
                  ],
                "CreateTokenRequest": [
                  { name: "name", type: "string" },
                  { name: "symbol", type: "string" },
                  { name: "deadline", type: "uint256" },
                  { name: "creator", type: "address" },
                  { name: "creatorSignatureNonce", type: "uint256" },
                  { name: "etherFee", type: "uint256" },
                  { name: "etherBuy", type: "uint256" },
                  { name: "initialMaxWalletBalance", type: "uint256" },
                  { name: "isDevLockup", type: "bool" },
                ],
                },
                "message": {
                  "name": name,
                  "symbol": symbol,
                  "deadline": deadline,
                  "creator": owner.address,
                  "creatorSignatureNonce": sigNonce.toString(),
                  "etherFee": etherFee.toString(),
                  "etherBuy": etherBuy.toString(),
                  "initialMaxWalletBalance": initialMaxWalletBalance.toString(),
                  "isDevLockup": isDevLockup,
                }
          
              }
          
              const domain = eip712Message['domain'];
              const message = eip712Message['message'];
              const types = {
                  [eip712Message["primaryType"]]: eip712Message['types'][eip712Message["primaryType"]]
              };
          
          
              const signature =await owner._signTypedData(domain, types, message);
          
              const recoveredAddress = ethers.utils.verifyTypedData(domain, types, message, signature);
              console.log("recoveredAddress",recoveredAddress);
        
              await parlayContract.connect(owner).createToken(name, symbol, deadline, etherFee, etherBuy, initialMaxWalletBalance, isDevLockup, sig.v, sig.r, sig.s, {value: ethers.utils.parseEther('0.1')})
            
        })

    })

})