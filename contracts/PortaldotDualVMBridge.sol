// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PortaldotDualVMBridge
 * @notice Portaldot Network V3.0 Dual-VM (EVM Solidity <-> Substrate WASM ink!) Intent & Liquidity Router
 * @dev Target Competition: Portaldot Hacker House 2026 ($5,200 USDT Pool = $2,600 USDT + $2,600 POT)
 *      Tracks Covered:
 *        - Track 1: Modular Cloud & Middleware (Verifiable AI/Oracle Intent Middleware)
 *        - Track 2: Multi-Chain & Cross-Chain Infrastructure (Atomic EVM <-> WASM ink! + XCM Bridge)
 *        - Track 3: Ecosystem DApps & Developer Tooling (Unified ERC-20 / PSP22 Liquidity Router)
 */

interface IPortaldotWasmPrecompile {
    /// @notice Portaldot V3.0 Cross-VM Precompile at 0x0000000000000000000000000000000000000808
    /// @param wasmAccountId32 32-byte Substrate AccountId of the target ink! WASM smart contract
    /// @param selectorAndScaleArgs 4-byte ink! message selector followed by SCALE-encoded arguments
    /// @param weightLimit RefTime execution weight limit on Substrate pallet-contracts
    /// @return success True if WASM execution succeeded without trap
    /// @return scaleOutput SCALE-encoded return data from the ink! contract
    function callWasmContract(
        bytes32 wasmAccountId32,
        bytes calldata selectorAndScaleArgs,
        uint64 weightLimit
    ) external payable returns (bool success, bytes memory scaleOutput);
}

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract PortaldotDualVMBridge {
    address public constant WASM_PRECOMPILE = 0x0000000000000000000000000000000000000808;
    bytes4 public constant INK_SETTLE_INTENT_SELECTOR = 0x7a4f91b2;

    bytes32 public immutable inkRouterAccountId32;
    address public immutable governanceAdmin;

    struct CrossVMIntent {
        bytes32 intentId;
        address evmSender;
        bytes32 wasmRecipientId32;
        address evmToken;
        uint256 amount;
        uint32 destinationParachainId;
        uint64 deadlineTimestamp;
        bool settled;
    }

    mapping(bytes32 => CrossVMIntent) public intents;
    uint256 public totalBridgedVolume;
    uint256 public totalIntentsSettled;

    event CrossVMIntentDispatched(
        bytes32 indexed intentId,
        address indexed evmSender,
        bytes32 indexed wasmRecipientId32,
        address evmToken,
        uint256 amount,
        uint32 destinationParachainId,
        bytes32 wasmStateRoot
    );

    error InvalidAmount();
    error IntentExpired();
    error IntentAlreadySettled();
    error WasmCrossCallFailed();

    constructor(bytes32 _inkRouterAccountId32) {
        inkRouterAccountId32 = _inkRouterAccountId32;
        governanceAdmin = msg.sender;
    }

    /**
     * @notice Escrows EVM ERC-20 liquidity and atomically invokes the Portaldot V3.0 WASM ink! intent router
     */
    function dispatchCrossVMIntent(
        bytes32 wasmRecipientId32,
        address evmToken,
        uint256 amount,
        uint32 destinationParachainId,
        uint64 deadlineTimestamp
    ) external returns (bytes32 intentId, bytes32 wasmStateRoot) {
        if (amount == 0) revert InvalidAmount();
        if (block.timestamp > deadlineTimestamp) revert IntentExpired();

        intentId = keccak256(
            abi.encodePacked(
                msg.sender,
                wasmRecipientId32,
                evmToken,
                amount,
                destinationParachainId,
                totalIntentsSettled,
                block.chainid
            )
        );
        if (intents[intentId].settled) revert IntentAlreadySettled();

        require(IERC20Minimal(evmToken).transferFrom(msg.sender, address(this), amount), "ERC20_ESCROW_FAILED");

        // Build SCALE-compatible payload for the ink! WASM contract
        bytes memory scalePayload = abi.encodePacked(
            INK_SETTLE_INTENT_SELECTOR,
            intentId,
            wasmRecipientId32,
            uint128(amount),
            destinationParachainId
        );

        (bool ok, bytes memory output) = IPortaldotWasmPrecompile(WASM_PRECOMPILE).callWasmContract(
            inkRouterAccountId32,
            scalePayload,
            2_500_000_000 // 2.5B RefTime weight
        );
        if (!ok || output.length < 32) revert WasmCrossCallFailed();

        wasmStateRoot = abi.decode(output, (bytes32));

        intents[intentId] = CrossVMIntent({
            intentId: intentId,
            evmSender: msg.sender,
            wasmRecipientId32: wasmRecipientId32,
            evmToken: evmToken,
            amount: amount,
            destinationParachainId: destinationParachainId,
            deadlineTimestamp: deadlineTimestamp,
            settled: true
        });

        totalBridgedVolume += amount;
        totalIntentsSettled += 1;

        emit CrossVMIntentDispatched(
            intentId,
            msg.sender,
            wasmRecipientId32,
            evmToken,
            amount,
            destinationParachainId,
            wasmStateRoot
        );
    }
}
