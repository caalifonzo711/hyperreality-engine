# Hyperreality Engine — Determinism Sprint

## Goal
Get the rollback fighter to deterministic authoritative convergence before adding more gameplay features.

## Success criteria
- 0/0/0 movement-only: 0 checksum mismatches
- 0/0/0 movement + jab: 0 checksum mismatches
- 0/0/3 movement + jab: 0 confirmed-frame checksum mismatches

## Rules
- Work one gate at a time.
- Do not rewrite the engine.
- Do not change languages.
- Do not touch combat or hitbox logic while working on match-start synchronization.
- Do not claim a two-PC test passed unless I actually run it.
- Before editing a gate, explain which files and code paths are involved.
- Make the smallest change possible.
- Stop after each gate and give me exact test instructions.

## Gate 1 — Match start synchronization
Ensure host/client start one logical match exactly once.

Acceptance:
- no repeated START messages
- both sessions reset to frame 0 once
- no large initial frame offset

## Gate 2 — Canonical state
Add an explicit ordered representation of authoritative rollback state.

## Gate 3 — Canonical checksum
Replace snapshot.hash() with an explicit deterministic checksum.

## Gate 4 — External mutation audit
Inspect gameplay-affecting mutations outside rollback simulation.

## Gate 5 — 0/0/0 movement
Require 0 mismatches.

## Gate 6 — 0/0/0 jab
Require 0 mismatches.

## Gate 7 — 0/0/3
Require 0 confirmed-frame mismatches.
