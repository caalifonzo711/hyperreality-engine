# Hyperreality Rollback Engine

A deterministic, rollback-ready simulation framework built in Godot.

> Minimal core. Deterministic by design. Rollback from first principles.

---

## Demo (hand-drawn indie game coming soon!) 

![Video Project](https://github.com/user-attachments/assets/98164da6-bc40-4574-aa19-e02dcefdd80a)


> Example: 2-player combat simulation with rollback-safe architecture

---

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

```

2. Replace the `.png` files with your own:
- your drawings
- pixel art
- AI-generated images
- literally anything

3. Keep the same filenames (or update paths if you know how)

4. Run the project

👉 That’s it — you now have your own animated, interactive character. Congratulations!

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

- ⚔️ melee combat (fast reactions)
- 🥊 fighting games (frame-perfect timing)
- 🎮 action games
- 🧠 strategy systems

Same core → different feel.

---

## Key Properties

- **Deterministic simulation** (fixed timestep, 60 Hz)
- **Frame-based logic** (no delta-time drift)
- **Rollback-ready architecture**
- **Input buffered per frame**
- **Simulation separated from rendering**

---

## Architecture

## Architecture

The project is structured around a deterministic simulation core.

- `ArenaScene` coordinates the demo
- `FighterRollbackAdapter` handles frame input, buffering, snapshot, and restore
- `PlayerState` stores authoritative gameplay state
- `CombatSystem` resolves interactions deterministically
- rendering reads from simulation state but does not author gameplay

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
```

ArenaScene
├── FighterRollbackAdapter
│     ├── Input Buffer
│     └── Snapshot System
├── PlayerState (authoritative state)
├── CombatSystem (deterministic interaction)
└── Rendering (read-only)

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

![Debug Overlay](./docs/debug_overlay.png)

Includes:
- tick-level inspection
- input tracking
- state verification

---

## Status

### Implemented
- deterministic simulation core
- local 2-player combat demo
- snapshot + restore

### In Progress
- online multiplayer (network transport)
- additional game demos

### Planned / Experimental
- AI-assisted tooling (Gemini integration)
- additional rollback-based projects
- Crypto shop integrations

---

## Use Cases

This is not limited to fighting games.

Potential uses:

- fighting / action games  
- RTS / tactics systems  
- co-op physics games  
- interactive story systems  

---

## Quick Start

```bash
git clone https://github.com/yourname/yourrepo
````

Open in Godot Engine and run:

```
FighterArena.tscn
```

---

## FAQ

**Is this multiplayer?**
Not yet — currently focused on deterministic correctness.

**Do I need to code to use it?**
No — you can swap art and experiment immediately.

**Is this just a fighting game?**
No — the combat demo is a reference for a reusable system.

---

## Collaboration

If you're:

* building a game
* experimenting with rollback
* or just want to mess with it

Open an issue or reach out.

---

## Philosophy

> Build small, deterministic systems that scale into anything.

This is:

* a working demo
* a foundation for future games
* an indie game passion project
* an evil plan to take over the world 
  
```Have fun, Happy coding!

## 🧠 Common Questions (Especially from OSS / Linux folks)

### Is this actually deterministic across machines?

Yes — the simulation is designed around:
- fixed timestep (60 Hz)
- frame-based state updates
- explicit state (no hidden engine-side mutation)

Current validation:
- rollback loopback produces identical final states
- snapshot + restore includes all gameplay-relevant variables

Cross-machine validation is the next step (network transport in progress).

---

### Is rollback fully implemented or just “planned”?

The **core rollback pieces are implemented**:
- snapshot
- restore
- deterministic simulation

What’s missing:
- real network transport (e.g. WebRTC / sockets)

Right now the system is:
→ **rollback-ready**, not fully networked yet

---

### Why use this instead of built-in engine networking?

Most engine networking assumes:
- latency compensation
- interpolation
- server authority

This project explores a different model:
→ **deterministic simulation + rollback**

Which enables:
- instant local responsiveness
- frame-accurate gameplay
- consistent results across clients

---

### Why :contentReference[oaicite:0]{index=0}?

- open source
- lightweight
- fast iteration
- no engine-level constraints on simulation design

The goal is:
→ keep the simulation model portable and understandable

---

### What exactly gets snapshotted?

All gameplay-relevant state, including:
- player position / velocity
- attack state + timers
- hit confirmation flags
- cooldowns
- hitstop

Rendering is NOT part of the snapshot.

---

### How big is the rollback window?

Currently small (a few frames) for testing.

This is configurable and depends on:
- network conditions
- game design requirements

---

### Is floating point determinism an issue?

Potentially, yes.

Current approach:
- controlled usage of physics/math
- deterministic update ordering

Future improvements may include:
- stricter constraints
- fixed-point or validation strategies if needed

---

### Is this only for fighting games?

No.

The combat demo is just a **reference implementation**.

The same architecture can support:
- action games
- RTS / tactics
- co-op simulations
- interactive systems

---

### Where does AI / Gemini fit in?

AI is **not part of the simulation loop**.

It is intended for:
- tooling
- content generation
- editor assistance

The simulation itself remains fully deterministic.

---

### Can I use this in my own project?

Yes — that’s the goal.

Right now:
- best used as a reference / starting point
- not yet a plug-and-play library

---

### Why open source this?

To:
- share a clean rollback-oriented architecture
- make deterministic simulation more accessible
- explore new types of real-time systems

---

### What’s the current priority?

1. Validate deterministic correctness  
2. Add real network transport  
3. Expand demos  
4. Build tooling around the system  

---

### Is this production-ready?

Not yet.

This is:
→ a working foundation + reference implementation

The focus is correctness first, then scale.
