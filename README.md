# Hyperreality Engine (Rollback Prototype)

A deterministic, rollback-ready simulation framework built in Godot.

This project provides a minimal, working example of how to structure real-time gameplay systems for rollback networking — with a simple 2-player combat demo as the reference implementation.

---

## What This Is

This is not just a fighting game.

It is a **deterministic simulation core** designed to be reused across different types of real-time games.

The included combat demo exists to:
- validate the architecture
- demonstrate rollback-safe patterns
- provide a concrete example for extension

---

## Features

- Fixed timestep simulation (60 Hz)
- Frame-based state machine (no delta-time drift)
- Deterministic input pipeline (buffered per frame)
- Complete snapshot + restore for rollback
- Velocity-based knockback (impulse + decay)
- Block + dodge (with invulnerability windows)
- Hurt and death states
- State-driven animation system
- Clean separation of gameplay vs rendering

---

## Architecture Overview

```text
ArenaScene
  → FighterRollbackAdapter (input + buffering + snapshot)
  → PlayerState (authoritative state)
  → CombatSystem (interaction logic)
  → Rendering (read-only)
