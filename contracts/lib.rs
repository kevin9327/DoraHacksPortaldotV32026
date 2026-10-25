#![cfg_attr(not(feature = "std"), no_std, no_main)]

/// Portaldot Network V3.0 — Substrate WASM (`ink!` v5) Dual-VM Intent & XCM Middleware Contract
/// Receives atomic cross-VM calls from `PortaldotDualVMBridge.sol` via Precompile `0x0808`,
/// updates PSP22 / XCM liquidity accounting, and returns a deterministic Blake2-256 state commitment.
#[ink::contract]
pub mod portaldot_wasm_intent_router {
    use ink::storage::Mapping;

    #[ink(storage)]
    pub struct PortaldotWasmIntentRouter {
        /// Authorized EVM Precompile caller mapped to Substrate AccountId
        evm_bridge_caller: AccountId,
        /// Maps 32-byte intent_id -> settled amount in atomic units
        settled_intents: Mapping<[u8; 32], u128>,
        /// Maps recipient AccountId -> PSP22 mirrored balance
        psp22_balances: Mapping<AccountId, u128>,
        /// Cumulative volume routed across EVM <-> WASM + XCM
        total_wasm_routed: u128,
        /// Latest deterministic state commitment root
        latest_state_root: [u8; 32],
    }

    #[ink(event)]
    pub struct WasmIntentSettled {
        #[ink(topic)]
        intent_id: [u8; 32],
        #[ink(topic)]
        recipient: AccountId,
        amount: u128,
        destination_para_id: u32,
        state_root: [u8; 32],
    }

    #[derive(Debug, PartialEq, Eq, scale::Encode, scale::Decode)]
    #[cfg_attr(feature = "std", derive(scale_info::TypeInfo))]
    pub enum RouterError {
        UnauthorizedEvmBridge,
        DuplicateIntent,
        ZeroLiquidityAmount,
    }

    impl PortaldotWasmIntentRouter {
        #[ink(constructor)]
        pub fn new(evm_bridge_caller: AccountId) -> Self {
            Self {
                evm_bridge_caller,
                settled_intents: Mapping::default(),
                psp22_balances: Mapping::default(),
                total_wasm_routed: 0,
                latest_state_root: [0u8; 32],
            }
        }

        /// Selector: 0x7a4f91b2 — Invoked atomically by Portaldot EVM Precompile 0x0808
        #[ink(message, selector = 0x7a4f91b2)]
        pub fn settle_cross_vm_intent(
            &mut self,
            intent_id: [u8; 32],
            recipient: AccountId,
            amount: u128,
            destination_para_id: u32,
        ) -> Result<[u8; 32], RouterError> {
            if self.env().caller() != self.evm_bridge_caller {
                return Err(RouterError::UnauthorizedEvmBridge);
            }
            if amount == 0 {
                return Err(RouterError::ZeroLiquidityAmount);
            }
            if self.settled_intents.contains(intent_id) {
                return Err(RouterError::DuplicateIntent);
            }

            self.settled_intents.insert(intent_id, &amount);
            let prev_bal = self.psp22_balances.get(recipient).unwrap_or(0);
            self.psp22_balances.insert(recipient, &(prev_bal.saturating_add(amount)));
            self.total_wasm_routed = self.total_wasm_routed.saturating_add(amount);

            // Compute new Blake2x256 state commitment across intent_id + total_wasm_routed + para_id
            let mut preimage = [0u8; 52];
            preimage[0..32].copy_from_slice(&intent_id);
            preimage[32..48].copy_from_slice(&self.total_wasm_routed.to_le_bytes());
            preimage[48..52].copy_from_slice(&destination_para_id.to_le_bytes());

            let mut state_root = [0u8; 32];
            ink::env::hash_bytes::<ink::env::hash::Blake2x256>(&preimage, &mut state_root);
            self.latest_state_root = state_root;

            self.env().emit_event(WasmIntentSettled {
                intent_id,
                recipient,
                amount,
                destination_para_id,
                state_root,
            });

            Ok(state_root)
        }

        #[ink(message)]
        pub fn get_recipient_balance(&self, account: AccountId) -> u128 {
            self.psp22_balances.get(account).unwrap_or(0)
        }

        #[ink(message)]
        pub fn get_total_wasm_routed(&self) -> u128 {
            self.total_wasm_routed
        }
    }
}
