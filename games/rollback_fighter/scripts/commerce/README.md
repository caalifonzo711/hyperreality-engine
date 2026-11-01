# Commerce Prototype

## Purpose

This module is a minimal, payment-agnostic commerce and entitlement prototype. It
demonstrates how products, redemption codes, and interchangeable purchase providers
can converge on one ownership boundary without entering rollback-authoritative state.

It is development scaffolding, not a production payment system.

## Runtime composition

`CommerceRuntime` is the composition root and application-session owner. It loads one
shared `ProductCatalog`, references the `EntitlementService` autoload, creates the active
`PrototypeCommerceProvider`, and configures one `CommerceService` and one
`RedemptionService` with those shared dependencies.

The individual services retain standalone initialization for focused tests, but normal
game startup uses the shared runtime instances.

```text
                  ProductCatalog
                        |
                        v
UI -> CommerceService -> CommerceProvider
          |                    |
          |               PurchaseResult
          |                    |
          +------ success -----+
          |
          v
EntitlementService
          |
          v
Game Content

RedemptionService
        |
        v
EntitlementService
```

Character Select asks only `EntitlementService.has_entitlement()` when deciding whether
product-backed content is available. It does not know how ownership was acquired.

## Current functionality

- Local product catalog and product lookup
- Entitlement-based content gating
- Development grant and revoke controls
- Development redemption codes
- Raw codes and `hyperreality://redeem?code=...` payloads
- One-time redemption during the application session
- Interchangeable `CommerceProvider` contract
- Prototype success, cancellation, failure, and unavailable results
- Prototype transaction/reference IDs
- Duplicate ownership protection
- Session-only successful transaction tracking
- Optional provider restore capability and purchase reconciliation

## Provider and reconciliation contracts

Providers implement:

```text
get_provider_id() -> String
purchase(product_id) -> PurchaseResult
supports_restore() -> bool
restore_purchases() -> Array[PurchaseResult]
```

`CommerceService.reconcile_purchases()` accepts only successful restored results with a
known catalog product, the active provider ID, and a non-empty transaction reference.
Valid results grant through `EntitlementService`; unknown, failed, cancelled, malformed,
and duplicate transaction results are ignored.

A production provider must be the trusted authority for restored purchases. Consider
this failure sequence:

```text
external provider reports SUCCESS
-> local entitlement grant fails or the application crashes
-> a later provider reconciliation verifies the transaction
-> CommerceService restores the entitlement
```

`EntitlementService` is an ownership view, not a payment ledger. It must not be treated
as the source of truth for recovering paid transactions.

## Future provider model

Future adapters could implement the same provider contract, for example:

- `SteamCommerceProvider`
- `GooglePlayCommerceProvider`
- `WebCommerceProvider`
- `CryptoCommerceProvider`

Adding a provider should not require changes to Character Select, fighter content, or
the entitlement gating logic.

## Deliberately absent

This prototype does not include:

- Real payment processing
- Production persistence
- User accounts
- Server validation
- Steam integration
- Google Play integration
- Apple in-app purchases
- Stripe
- PayPal
- Crypto payments
- Wallets
- Blockchain
- NFTs
- Creator marketplace
- Creator payouts
- Revenue splitting
- Taxes
- Refunds
- Fraud prevention

## Current limitations

- Ownership, redeemed codes, transaction history, and provider counters are session-only.
- Static development redemption codes are public and insecure.
- Prototype transaction IDs are not trusted financial identifiers.
- Prototype restore fixtures are not verified external transactions.
- The current test "skin" is a complete alternate fighter definition.
- A true presentation-only cosmetic identity and selection layer is future work.

No commerce data belongs in deterministic gameplay, rollback snapshots, checksums,
combat configuration, hitboxes, prediction, or network transport.
