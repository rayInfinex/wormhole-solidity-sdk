// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../src/interfaces/IWormholeRelayer.sol";
import "../../src/interfaces/IWormhole.sol";
import "../../src/interfaces/ITokenBridge.sol";
import "../../src/Utils.sol";

import "./helpers/WormholeSimulator.sol";
import "./ERC20Mock.sol";
import "./helpers/DeliveryInstructionDecoder.sol";
import "./helpers/ExecutionParameters.sol";
import "./helpers/MockOffchainRelayer.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

struct ChainInfo {
    uint16 chainId;
    string url;
    IWormholeRelayer relayer;
    ITokenBridge tokenBridge;
    IWormhole wormhole;
}

abstract contract WormholeRelayerTest is Test {
    uint256 constant DEVNET_GUARDIAN_PK =
        0xcfb12303a19cde580bb4dd771639b0d26bc68353645571a8cff516ab2ee113a0;

    mapping(uint16 => ChainInfo) public chainInfosTestnet;

    uint16 public sourceChain;
    uint16 public targetChain;

    uint256 public sourceFork;
    uint256 public targetFork;

    IWormholeRelayer public relayerSource;
    ITokenBridge public tokenBridgeSource;
    IWormhole public wormholeSource;

    IWormholeRelayer public relayerTarget;
    ITokenBridge public tokenBridgeTarget;
    IWormhole public wormholeTarget;

    WormholeSimulator public guardianSource;
    WormholeSimulator public guardianTarget;

    MockOffchainRelayer public mockOffchainRelayer;

    constructor() {
        console.log("In WormholeRelayerTest constructor");
        initChainInfo();
        setForkChains(6, 14);
    }

    function setUpSource() public virtual;

    function setUpTarget() public virtual;

    function setForkChains(uint16 _sourceChain, uint16 _targetChain) public {
        console.log("In setForkChains");
        sourceChain = _sourceChain;
        relayerSource = chainInfosTestnet[sourceChain].relayer;
        tokenBridgeSource = chainInfosTestnet[sourceChain].tokenBridge;
        wormholeSource = chainInfosTestnet[sourceChain].wormhole;

        relayerTarget = chainInfosTestnet[_targetChain].relayer;
        tokenBridgeTarget = chainInfosTestnet[_targetChain].tokenBridge;
        wormholeTarget = chainInfosTestnet[_targetChain].wormhole;

        targetChain = _targetChain;
    }

    function setUp() public {
        console.log(sourceChain);
        console.log(chainInfosTestnet[sourceChain].chainId);
        console.log(chainInfosTestnet[sourceChain].url);

        sourceFork = vm.createSelectFork(chainInfosTestnet[sourceChain].url);
        guardianSource = new WormholeSimulator(
            address(wormholeSource),
            DEVNET_GUARDIAN_PK
        );

        targetFork = vm.createSelectFork(chainInfosTestnet[targetChain].url);
        guardianTarget = new WormholeSimulator(
            address(wormholeTarget),
            DEVNET_GUARDIAN_PK
        );

        vm.selectFork(sourceFork);
        setUpSource();
        vm.selectFork(targetFork);
        setUpTarget();

        vm.selectFork(sourceFork);

        mockOffchainRelayer =
            new MockOffchainRelayer(address(wormholeSource), address(guardianSource), vm);
        mockOffchainRelayer.registerChain(sourceChain, address(relayerSource), sourceFork);
        mockOffchainRelayer.registerChain(targetChain, address(relayerTarget), targetFork);

        // Allow the offchain relayer to work on both source and target fork
        vm.makePersistent(address(mockOffchainRelayer));
    }

    function performDelivery() public {
        performDelivery(vm.getRecordedLogs());
    }

    function performDelivery(Vm.Log[] memory logs, bool debugLogging) public {
        require(logs.length > 0, "no events recorded");
        mockOffchainRelayer.relay(logs, debugLogging);
    }

    function performDelivery(Vm.Log[] memory logs) public {
        require(logs.length > 0, "no events recorded");
        mockOffchainRelayer.relay(logs);
    }

    function createAndAttestToken(uint256 fork) public returns (ERC20Mock token) {
        vm.selectFork(fork);

        token = new ERC20Mock("Test Token", "TST");
        token.mint(address(this), 5000e18);

        ITokenBridge tokenBridge =
            fork == sourceFork ? tokenBridgeSource : tokenBridgeTarget;
        vm.recordLogs();
        tokenBridge.attestToken(address(token), 0);
        WormholeSimulator guardian = fork == sourceFork ? guardianSource : guardianTarget;
        Vm.Log memory log = guardian.fetchWormholeMessageFromLog(vm.getRecordedLogs())[0];
        uint16 chainId = fork == sourceFork ? sourceChain : targetChain;
        bytes memory attestation = guardian.fetchSignedMessageFromLogs(log, chainId);

        vm.selectFork(fork == sourceFork ? targetFork : sourceFork);
        tokenBridge = fork == sourceFork ? tokenBridgeTarget : tokenBridgeSource;
        tokenBridge.createWrapped(attestation);
        vm.selectFork(fork);
    }

    function logFork() public view {
        console.log(
            vm.activeFork() == sourceFork ? "source fork active" : "target fork active"
        );
    }

    function initChainInfo() private {
        chainInfosTestnet[6] = ChainInfo({
            chainId: 6,
            url: "https://api.avax-test.network/ext/bc/C/rpc",
            relayer: IWormholeRelayer(0xA3cF45939bD6260bcFe3D66bc73d60f19e49a8BB),
            tokenBridge: ITokenBridge(0x61E44E506Ca5659E6c0bba9b678586fA2d729756),
            wormhole: IWormhole(0x7bbcE28e64B3F8b84d876Ab298393c38ad7aac4C)
        });
        chainInfosTestnet[14] = ChainInfo({
            chainId: 14,
            url: "https://alfajores-forno.celo-testnet.org",
            relayer: IWormholeRelayer(0x306B68267Deb7c5DfCDa3619E22E9Ca39C374f84),
            tokenBridge: ITokenBridge(0x05ca6037eC51F8b712eD2E6Fa72219FEaE74E153),
            wormhole: IWormhole(0x88505117CA88e7dd2eC6EA1E13f0948db2D50D56)
        });

        chainInfosTestnet[4] = ChainInfo({
            chainId: 4,
            url: "https://bsc-testnet.public.blastapi.io",
            relayer: IWormholeRelayer(0x80aC94316391752A193C1c47E27D382b507c93F3),
            tokenBridge: ITokenBridge(0x9dcF9D205C9De35334D646BeE44b2D2859712A09),
            wormhole: IWormhole(0x68605AD7b15c732a30b1BbC62BE8F2A509D74b4D)
        });

        chainInfosTestnet[5] = ChainInfo({
            chainId: 5,
            url: "https://matic-mumbai.chainstacklabs.com",
            relayer: IWormholeRelayer(0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0),
            tokenBridge: ITokenBridge(0x377D55a7928c046E18eEbb61977e714d2a76472a),
            wormhole: IWormhole(0x0CBE91CF822c73C2315FB05100C2F714765d5c20)
        });

        chainInfosTestnet[16] = ChainInfo({
            chainId: 16,
            url: "https://rpc.testnet.moonbeam.network",
            relayer: IWormholeRelayer(0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0),
            tokenBridge: ITokenBridge(0xbc976D4b9D57E57c3cA52e1Fd136C45FF7955A96),
            wormhole: IWormhole(0xa5B7D85a8f27dd7907dc8FdC21FA5657D5E2F901)
        });
    }

    receive() external payable {}
}
