# Hyperreality Rollback Engine

A deterministic, rollback-ready simulation framework built in Godot.

> Minimal core. Deterministic by design. Rollback from first principles.
> 
> ⚠️ NOTE: AI / Gemini tools are not functional yet.
Only the rollback demo (FighterArena.tscn) is currently working.
---

## Demo (hand-drawn indie game coming soon!) 

![Video Project](https://github.com/user-attachments/assets/98164da6-bc40-4574-aa19-e02dcefdd80a)

## Try this first

1. Open `FighterArena.tscn`
2. Press F6
3. Try attacking and moving

What to look for:
- instant responsiveness
- consistent hit behavior
- rollback-safe interactions

## 🧠 What This Is

This project provides a **deterministic simulation core** for real-time games.

It is designed to:
- guarantee identical outcomes across machines
- support rollback-based multiplayer
- be reused across different types of games

The included combat demo is a **reference implementation**.

---

## 🎮 Just Want to Try It? (No Coding Required)

You can use this like a **toy / sandbox**.

### ✨ Replace the art with your own

1. Go to:

```

games/rollback_fighter/characters/example_fighter/sprites/

````

2. Replace the `.png` files with your own:
- your drawings
- pixel art
- AI-generated images
- literally anything

3. Keep the same filenames (or update paths if you know how)

4. Run the project

👉 That’s it — you now have your own animated, interactive character.

---

### 🧪 What you’ll see

- Your character moves  
- Attacks trigger  
- Hit reactions happen  
- Everything runs in a **deterministic simulation**

No coding required to experiment.

---

## 🔄 What is Rollback? (Simple Explanation)

Most games:
- lag = everything slows down

Rollback works differently:

👉 The game **keeps running instantly**, then fixes mistakes afterward.

### Concept:

1. You press a button  
2. Game responds immediately  
3. If the other player's input arrives late:
   - game rewinds a few frames
   - re-simulates correctly  

You don’t notice — it feels smooth.

---

### Why this matters

This system can be tuned for:

- ⚔️ melee combat  
- 🥊 fighting games (frame-perfect timing)  
- 🎮 action games  
- 🧠 strategy systems  

Same core → different feel.

---

## Key Properties

- Deterministic simulation (fixed timestep, 60 Hz)  
- Frame-based logic (no delta-time drift)  
- Rollback-ready architecture  
- Input buffered per frame  
- Simulation separated from rendering  

---

## Architecture

The project is structured around a deterministic simulation core.

- `ArenaScene` coordinates the demo  
- `FighterRollbackAdapter` handles frame input, buffering, snapshot, and restore  
- `PlayerState` stores authoritative gameplay state  
- `CombatSystem` resolves interactions deterministically  
- Rendering reads from simulation state but does not author gameplay  

```text
                          ┌───────────────────────┐
                          │    FighterArena.tscn  │
                          │   (top-level scene)   │
                          └───────────┬───────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
   ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
   │ FighterRollback  │    │   PlayerState    │    │   PlayerState    │
   │     Adapter      │───▶│    (Player 1)    │    │    (Player 2)    │
   │                  │    │ authoritative     │    │ authoritative     │
   │ - input buffer   │    │ gameplay state    │    │ gameplay state    │
   │ - frame input    │    └──────────────────┘    └──────────────────┘
   │ - snapshot       │              │                       │
   │ - restore        │              └───────────┬───────────┘
   └────────┬─────────┘                          │
            │                                    ▼
            │                         ┌──────────────────┐
            └────────────────────────▶│   CombatSystem   │
                                      │ deterministic    │
                                      │ interaction      │
                                      │ resolution       │
                                      └────────┬─────────┘
                                               │
                                               ▼
                                      ┌──────────────────┐
                                      │    Rendering     │
                                      │   read-only      │
                                      │ visual output    │
                                      └──────────────────┘
````

---

## Rollback Model

Each frame:

1. Input is buffered
2. Simulation advances
3. State is saved
4. On mismatch → rollback + re-simulate

Result:
→ identical final state across runs

---

## Debug / Validation

Includes:

* tick-level inspection
* input tracking
* state verification

---

## Status

### Implemented

* deterministic simulation core
* local 2-player combat demo
* snapshot + restore

### In Progress

* online multiplayer (network transport)
* additional game demos

### Planned / Experimental

* AI-assisted tooling (Gemini integration)
* additional rollback-based projects

---

## Use Cases

This is not limited to fighting games.

Potential uses:

* fighting / action games
* RTS / tactics systems
* co-op physics games
* interactive systems

---

## Quick Start

```bash
git clone https://github.com/caalifonzo711/hyperreality-engine.git
```

Open in Godot and run:

```
FighterArena.tscn
```

---

## Run (Quick)

1. Open in Godot 4.x
2. Press F6 on `FighterArena.tscn`

---

## FAQ

**Is this multiplayer?**
Not yet — currently focused on deterministic correctness.

**Do I need to code to use it?**
No — you can swap art and experiment immediately.

**Is this just a fighting game?**
No — the combat demo is a reference for a reusable system.

---

## 🧠 Common Questions (Especially from OSS / Linux folks)

### Is this actually deterministic across machines?

Yes — the simulation is designed around:

* fixed timestep (60 Hz)
* frame-based state updates
* explicit state (no hidden engine-side mutation)

Current validation:

* rollback loopback produces identical final states
* snapshot + restore includes all gameplay-relevant variables

Cross-machine validation is the next step.

---

### Is rollback fully implemented or just “planned”?

The core rollback pieces are implemented:

* snapshot
* restore
* deterministic simulation

What’s missing:

* real network transport (e.g. WebRTC / sockets)

→ rollback-ready, not fully networked yet

---

### Why use this instead of built-in engine networking?

Most engine networking assumes:

* latency compensation
* interpolation
* server authority

This project explores:
→ deterministic simulation + rollback

Which enables:

* instant responsiveness
* frame-accurate gameplay
* consistent results across clients

---

### Why Godot?

* open source
* lightweight
* fast iteration
* no engine-level constraints on simulation design

Goal:
→ keep the simulation model portable and understandable

---

### What exactly gets snapshotted?

All gameplay-relevant state:

* position / velocity
* attack state + timers
* hit confirmation flags
* cooldowns
* hitstop

Rendering is NOT included.

---

### Is floating point determinism an issue?

Potentially, yes.

Current approach:

* controlled math usage
* deterministic update ordering

Future:

* stricter constraints or fixed-point if needed

---

### Can I use this in my own project?

Yes — that’s the goal.

Currently:

* best used as a reference / starting point

---

### Is this production-ready?

Not yet.

→ working foundation + reference implementation

---

## Collaboration

If you're:

* building a game
* experimenting with rollback
* or just curious

Open an issue or share feedback.

---

## Philosophy

> Build small, deterministic systems that scale into anything.

This is:

* a working demo
* a foundation for future games
* an indie experiment

Have fun.

---

## License

MIT

---

built by Alonso Rojas
linkedin: [https://www.linkedin.com/in/alonso-rojas-617546126/](https://www.linkedin.com/in/alonso-rojas-617546126/)

