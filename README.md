# Portaldot Omni-VM Nexus: Atomic EVM Solidity $\leftrightarrow$ Substrate WASM (`ink!`) Intent & XCM Router

![Portaldot Omni-VM Nexus Banner](./banner.png)

> **Target Competition:** **Portaldot Hacker House 2026** (`$5,200 USDT` Cash Pool = `$2,600 USDT + $2,600 POT`, closes November 5, 2026 on DoraHacks: `https://dorahacks.io/hackathon/portaldot-hacker-house-2026`)  
> **Tracks Covered:**
> 1. **Modular Cloud & Middleware** — Verifiable cross-VM intent middleware with deterministic `Blake2b-256` state commitments.
> 2. **Multi-Chain & Cross-Chain Infrastructure** — Single-block atomic invocation from **Portaldot EVM (`Solidity 0.8.24`)** into **Portaldot Substrate WASM (`ink! v5` Rust)** via Precompile `0x0000000000000000000000000000000000000808` and XCM parachain routing.
> 3. **Ecosystem DApps & Developer Tooling** — Unified `ERC-20` $\leftrightarrow$ `PSP22` liquidity accounting with replay and caller-spoofing protection.

---

## 1. Architecture & Dual-VM Innovation

Portaldot Network V3.0 runs both Frontier EVM (`pallet-evm`) and Substrate WASM (`pallet-contracts`) inside the same runtime, yet liquidity and developer tooling typically remain siloed between Solidity `ERC-20` tokens and Rust `ink!` `PSP22` contracts.

**Portaldot Omni-VM Nexus** unifies both virtual machines within a single atomic transaction:
1. **EVM Ingress ([`contracts/PortaldotDualVMBridge.sol`](./contracts/PortaldotDualVMBridge.sol)):** Escrows `ERC-20` (`USDT` / `POT`), computes a unique `intentId`, and encodes a SCALE call payload prefixed with `ink!` selector `0x7a4f91b2`.
2. **Precompile `0x0808` Dispatch:** Invokes `IPortaldotWasmPrecompile(0x0000000000000000000000000000000000000808).callWasmContract(...)` with a `2.5B` RefTime weight budget.
3. **WASM `ink!` Settlement ([`contracts/lib.rs`](./contracts/lib.rs)):** Verifies `env().caller() == evm_bridge_caller`, prevents duplicate intent replay, mints/credits the mirrored `PSP22` balance, and returns a 32-byte `Blake2x256` state commitment back to the EVM transaction log.

---

## 2. Repository Structure

| File | Description |
| :--- | :--- |
| [`contracts/PortaldotDualVMBridge.sol`](./contracts/PortaldotDualVMBridge.sol) | EVM Solidity contract escrowing ERC-20 liquidity and calling WASM Precompile `0x0808`. |
| [`contracts/lib.rs`](./contracts/lib.rs) | Substrate WASM `#[ink::contract]` Rust router settling cross-VM intents & computing `Blake2x256` state roots. |
| [`verify_portaldot_v3.py`](./verify_portaldot_v3.py) | Deterministic Dual-VM state transition & security invariant verifier + `banner.png` generator. |
| [`portaldot_v3_verification_report.json`](./portaldot_v3_verification_report.json) | Machine-verifiable output of all 4 Dual-VM execution & security test vectors (`4/4` passed). |
| [`index.html`](./index.html) | Interactive Dual-VM Intent Explorer & Cross-VM State Commitment Dashboard. |
| [`banner.png`](./banner.png) | `1200x630` DoraHacks BUIDL cover banner. |

---

## 3. One-Command Verification

```bash
python verify_portaldot_v3.py
```
