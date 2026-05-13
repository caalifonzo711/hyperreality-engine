# Hyperreality Rollback Engine

A deterministic, rollback-ready simulation framework built in Godot.

> Minimal core. Deterministic by design. Rollback from first principles.

Now featuring:
- synchronized two-PC rollback prototype over ENet
- frame-indexed input prediction + replay
- rollback correction metrics
- hand-drawn animated combat demo with updated color art

<img width="426" height="240" alt="Video Project 3" src="https://github.com/user-attachments/assets/556343c1-8d41-4d70-9477-9be47c21a5bc" />



⚠️ NOTE:
AI / Gemini tooling is still experimental.

The rollback fighter demo is currently the primary working showcase.

---

# 🎮 Current Demo — Rollback Fighter Prototype

The project now includes a working two-computer rollback prototype.

Current features:
- synchronized two-PC rollback sessions
- frame-indexed input packets
- prediction + replay
- rollback metrics HUD
- synchronized match start
- rollback-safe combat state
- updated hand-drawn color character art
- deterministic combat simulation

The original prototype used programmer placeholder drawings.

The current version now includes:
- colored character sprites
- stage art integration
- animated fighter placeholders
- early indie game presentation polish

Still intentionally lightweight while networking systems are stabilized.

---

# 🚀 Quick Start

## Clone

```bash
git clone https://github.com/caalifonzo711/hyperreality-engine.git
````

Open in Godot 4.x.

---

# ▶️ Run Local Demo

Open:

```text
FighterArena.tscn
```

Press:

```text
F6
```

You can immediately:

* move
* attack
* block
* dodge
* test rollback-safe combat interactions

---

# 🌐 Run Two-PC Rollback Test

Desktop:

```gdscript
const ENET_HOST := true
```

Laptop:

```gdscript
const ENET_HOST := false
const ENET_IP := "YOUR_DESKTOP_IP"
```

Run desktop first.
Run laptop second.

Once both connect:

* press Enter on host
* synchronized rollback session begins

Current debug HUD tracks:

* packets received
* last remote frame
* rollback count
* max rollback depth
* prediction misses

---

# 🧠 What This Is

This project provides a deterministic simulation core for real-time games.

It is designed to:

* guarantee identical outcomes across machines
* support rollback-based multiplayer
* remain transport-agnostic
* scale into different game genres

The included combat demo is a reference implementation.

---

# 🔄 What is Rollback?

Most multiplayer games:

* delay your actions
* wait for the network
* feel sluggish under latency

Rollback works differently.

The game:

1. responds immediately
2. predicts missing remote input
3. receives delayed truth later
4. rewinds old frames
5. re-simulates forward
6. corrects reality

Result:

* instant responsiveness
* frame-accurate gameplay
* smoother online feel

---

# 🧪 Current Rollback Prototype

Current rollback flow:

```text
Input
↓
RollbackNetworkSession
↓
Prediction
↓
Snapshot History
↓
Late Packet Arrival
↓
Rollback + Replay
↓
Corrected Present
```

The rollback layer is intentionally separated from networking transport.

Current transport:

* ENet

Planned transports:

* WebRTC
* relay servers
* replay systems
* custom transports

without modifying gameplay simulation logic.

---

# ⚙️ Current Architecture

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
   │ RollbackNetwork  │    │   PlayerState    │    │   PlayerState    │
   │     Session      │───▶│    (Player 1)    │    │    (Player 2)    │
   │                  │    │ authoritative     │    │ authoritative     │
   │ - input buffer   │    │ gameplay state    │    │ gameplay state    │
   │ - prediction     │    └──────────────────┘    └──────────────────┘
   │ - rollback       │              │                       │
   │ - replay         │              └───────────┬───────────┘
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

---

# 🛰️ Current Networking Architecture

```text
Desktop Host
↓
ENetTransport
↓
Frame-indexed input packets
↓
RollbackNetworkSession
↓
Prediction + Snapshot History
↓
Rollback Replay
↓
Client
```

Current status:

* LAN rollback sessions working
* synchronized match start working
* rollback replay active
* bounded rollback correction observed
* live packet metrics available

In progress:

* checksum/desync validation
* artificial latency + jitter testing
* input-delay tuning
* transport refinement

---

# 🧪 Current Validation

Current validation includes:

* rollback replay convergence
* synchronized two-PC ENet sessions
* bounded rollback correction on LAN
* frame-indexed remote input replay

Observed:

* rollback corrections occurring successfully
* low rollback depth during LAN tests
* stable packet flow between clients

Current focus:

* 100ms / 150ms / 200ms stress testing
* checksum validation
* jitter handling
* tuning online responsiveness

---

# 🎨 Art / Visual Workflow

The project intentionally supports rapid visual iteration.

You can replace the art immediately.

Go to:

```text
games/rollback_fighter/characters/example_fighter/sprites/
```

Replace PNGs with:

* your drawings
* pixel art
* AI-generated art
* placeholder images

Run the project again.

The rollback systems remain unchanged.

---

# ⚔️ Current Gameplay Systems

Implemented:

* movement
* attacks
* hit reactions
* block
* dodge
* hitstop
* cooldowns
* rollback replay
* synchronized multiplayer session start

---

# 🧠 Determinism Model

The engine uses:

* fixed timestep simulation
* frame-based state updates
* deterministic update ordering
* explicit gameplay state

Rendering is NOT authoritative.

Gameplay simulation drives rendering.

---

# 🧪 Debug / Validation Tools

Current tools:

* rollback metrics HUD
* packet counters
* remote frame tracking
* prediction miss tracking
* rollback depth tracking
* replay validation

Future:

* checksum comparison
* replay export
* deterministic replay validation
* desync inspection tooling

---

# 📌 Current Status

## Implemented

* deterministic simulation core
* rollback replay loop
* synchronized two-PC ENet prototype
* frame-indexed prediction
* rollback correction metrics
* rollback-safe combat demo
* color art integration

## In Progress

* higher latency benchmarking
* checksum validation
* transport abstraction refinement
* rollback feel tuning

## Planned

* additional game demos
* AI-assisted tooling
* replay systems
* expanded rollback framework

---

# 🎮 Potential Use Cases

This is not limited to fighting games.

Potential applications:

* fighting / action games
* RTS / tactics systems
* co-op physics games
* simulation sandboxes
* educational systems
* experimental multiplayer projects

---

# ❓ FAQ

## Is this multiplayer?

Yes.

The current prototype supports:

* synchronized two-PC rollback sessions
* prediction + replay
* rollback correction
* ENet-based LAN testing

The networking layer is still experimental.

---

## Is rollback actually implemented?

Yes.

Current rollback systems include:

* snapshot capture
* restore
* replay
* prediction correction
* rollback metrics

---

## Is this production-ready?

Not yet.

Current state:

* functioning prototype
* rollback architecture validation
* deterministic networking experiments

---

## Why Godot?

* open source
* lightweight
* fast iteration
* portable simulation architecture
* transparent engine behavior

Goal:

* understandable deterministic systems
* transport-independent rollback architecture

---

## Is floating point determinism a concern?

Potentially, yes.

Current approach:

* controlled math usage
* deterministic update ordering
* bounded simulation scope

Future options:

* stricter constraints
* fixed-point arithmetic if needed

---

# 🤝 Collaboration

If you're:

* building rollback systems
* experimenting with deterministic networking
* exploring multiplayer architecture
* or just curious

Open an issue or share feedback.

---

# Philosophy

> Build small deterministic systems that scale into anything.

Current priorities:

* deterministic simulation
* rollback correctness
* transport-independent architecture
* understandable systems
* rapid iteration

Small systems first.
Then synchronization.
Then scale.

---

# License

MIT

---

built by Alonso Rojas

LinkedIn:
[https://www.linkedin.com/in/alonso-rojas-617546126/](https://www.linkedin.com/in/alonso-rojas-617546126/)

```
```


