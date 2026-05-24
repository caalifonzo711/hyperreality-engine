# SyncStrike QA Benchmark Demo — Gemini Rollback Fighter
<img width="426" height="240" alt="Video Project 3" src="https://github.com/user-attachments/assets/46603c88-e152-46e4-9287-bebcbb2eb5f4" />



A deterministic rollback multiplayer fighter with Gemini-generated move data and automated two-PC QA benchmarking.
# HyperRobotics — Rollback Interaction Systems for Physical AI

## HackStorm 2.0 Submission Concept

HyperRobotics explores how fighting-game-grade interaction systems can improve real-time robotics responsiveness.

Most robotics systems focus on autonomy, navigation, or task completion. Our focus is different:

```text
How do we make physical AI feel responsive,
predictable,
and expressive in real time?
```

This project applies deterministic rollback architecture, state-machine-driven interaction design, and low-latency multiplayer synchronization principles from competitive games to physical robotics systems.

## Core Idea

```text
Human Input
↓
Gemini Intent Parsing
↓
Deterministic Robot Command State
↓
Rollback-Safe Action Pipeline
↓
Robot Adapter Layer
↓
Physical Robotics Motion
```

Instead of allowing AI to directly control robotics behavior, Gemini only generates structured command data.

The engine remains authoritative over:

* timing
* motion states
* rollback safety
* deterministic replay
* synchronization
* interaction constraints

This separation allows AI-assisted robotics behavior without sacrificing simulation stability or predictable interaction.

## Why This Matters

Most AI robotics demos are:

* asynchronous
* high-latency
* difficult to predict
* disconnected from human timing expectations

HyperRobotics investigates whether game-engine interaction systems can improve:

* robotics responsiveness
* remote robotics synchronization
* expressive motion behavior
* latency compensation
* human-machine interaction feel

## Key Technical Concepts

* Deterministic state machines
* Rollback-inspired correction architecture
* Input prediction
* Structured AI command generation
* Transport-agnostic robotics adapters
* Multiplayer synchronization concepts
* Real-time interaction systems

## Robotics Transport Architecture

The system abstracts robotics hardware behind adapter layers:

```text
Engine Command
↓
Robot Adapter
↓
CAN / Robotics Transport
↓
Physical Arm
```

This allows the same interaction architecture to target:

* simulated robotics
* physical robotics arms
* remote synchronized robotics
* AI-assisted control systems

## Inspiration

This work is inspired by:

* fighting-game rollback networking
* real-time multiplayer synchronization
* robotics interaction design
* low-latency control systems
* expressive animation state machines

## Current Prototype Status

Implemented:

* Gemini command parsing
* rollback-inspired robotics state machine
* deterministic action architecture
* live robot command generation
* Windows CAN adapter connectivity
* Python robotics bridge layer
* Godot real-time robotics UI
* transport abstraction architecture

In progress:

* direct Piper SDK hardware control
* motion profile tuning
* synchronized dual-arm experiments
* remote robotics interaction research

## HyperRobotics Vision

The long-term vision is to explore:

```text
“Can physical AI interaction feel as responsive,
predictable,
and expressive
as a competitive multiplayer game?”
```

This extends the user’s earlier rollback networking and Gemini integration work into physical robotics interaction systems. 

## What This Demo Shows

This demo proves three things at once:

1. **Rollback networking works across two computers**
2. **Gemini can generate fighting-game move data**
3. **The generated move becomes part of the deterministic rollback simulation**

In other words:

```text
Gemini prompt
↓
Generated move JSON
↓
Rollback fighter loads move
↓
Two machines connect
↓
Press Enter
↓
Automated QA match runs
↓
Logs prove synchronization + generated move behavior
````

This is not just an AI text demo. It is AI-generated gameplay data running inside a real-time deterministic multiplayer system.

---

# Why It Matters

Most AI demos are asynchronous: chatbots, dashboards, RAG apps, content tools.

This project asks a harder question:

> Can AI-generated content safely enter a real-time rollback multiplayer system without breaking determinism?

Our answer:

> Yes — if Gemini only generates structured data, while the rollback engine remains authoritative.

Gemini does **not** control the simulation.
Gemini generates rollback-safe move config data.

The engine decides how to load, validate, simulate, rollback, and replay.

---

# Core Demo Concept

Gemini generates a move like:

```json
{
  "name": "strong kick",
  "startup": 8,
  "active": 4,
  "recovery": 15,
  "on_hit": 2,
  "on_block": -4
}
```

That move is saved as JSON and injected into the fighter as the generated heavy attack.

When the QA benchmark runs, the output logs show the generated move being loaded and used.

Look for console lines like:

```text
[GeminiMove] Loaded generated heavy move
[GeminiMove] Starting heavy
```

That confirms the Gemini-generated strike entered the gameplay simulation.

---

# API Key Setup

Create a Gemini API key from Google AI Studio.

On Windows PowerShell:

```powershell
setx GEMINI_API_KEY "YOUR_API_KEY_HERE"
```

Then restart:

* Godot
* terminal
* editor

The project loads the key from:

```gdscript
OS.get_environment("GEMINI_API_KEY")
```

If the key is detected, logs should show:

```text
GeminiClient: API key detected
```

---

# Two-PC QA Benchmark Setup

This demo is designed to run on two machines.

Example:

* Desktop = host
* Laptop = client

Both machines should have the project cloned and opened in Godot.

---

# Network Setup

You can connect machines using:

* same WiFi/LAN
* Tailscale
* other private VPN / direct IP setup

## Recommended: Tailscale

1. Install Tailscale on both machines.
2. Log into the same Tailscale account/network.
3. Confirm both machines can see each other.
4. Copy the host machine’s Tailscale IP.
5. Put that IP into the client config.

Host:

```gdscript
const ENET_HOST := true
```

Client:

```gdscript
const ENET_HOST := false
const ENET_IP := "HOST_TAILSCALE_OR_LAN_IP"
```

Run the host first.
Run the client second.

---

# Running the QA Demo

Once both machines connect:

```text
Press Enter on the host
```

The QA benchmark should begin automatically on both computers.

The system will run a deterministic test match and print benchmark output.

---

# What To Look For In The Output

Important lines:

```text
GeminiClient: API key detected
GeminiClient: Using schema 'fighter_move'
Gemini panel saved config to: res://games/rollback_fighter/moves/move_strong_kick.json
[GeminiMove] Loaded generated heavy move
[GeminiMove] Starting heavy
```

These prove:

* Gemini connected
* Gemini generated move data
* JSON was saved
* fighter loaded the move
* generated move entered gameplay

---

# Rollback QA Metrics

The benchmark output may include:

```text
Packets
LastRemoteFrame
LocalFrame
FrameGap
RollbackCount
MaxRollbackDepth
PredictionMisses
InputDelayFrames
```

What these mean:

## Packets

Network messages received.

## LocalFrame

Current simulation frame on this machine.

## LastRemoteFrame

Latest frame received from the remote player.

## FrameGap

Difference between local and remote frame progress.

## RollbackCount

How many times the engine corrected prediction using late remote input.

## MaxRollbackDepth

Largest rollback window observed.

## PredictionMisses

How often predicted input differed from actual input.

## InputDelayFrames

Intentional input delay used to stabilize rollback feel.

---

# What Success Looks Like

A successful run means:

* both machines connect
* pressing Enter starts the benchmark
* simulation runs automatically
* rollback metrics appear
* generated Gemini move logs appear
* both clients stay stable through the test

The key result:

> Gemini-generated move data successfully enters a deterministic rollback multiplayer simulation.

---

# Demo Script For Judges

1. “This is a rollback multiplayer fighter running across two machines.”
2. “Gemini generates structured move data, not gameplay logic.”
3. “The move is saved as JSON and injected into the deterministic fighter state machine.”
4. “Once both machines connect, we press Enter and the QA benchmark runs automatically.”
5. “The logs show rollback metrics and the Gemini-generated move being used.”
6. “The important point is that AI content enters the game without breaking rollback determinism.”

---

# Why This Is Not Just A Toy Demo

The architecture separates AI from simulation authority.

Gemini can generate:

* move data
* startup frames
* active frames
* recovery frames
* balance values

Gemini cannot directly modify:

* rollback logic
* network logic
* physics
* combat simulation authority
* deterministic replay behavior

That separation is what makes the system safe.

---

# Current Status

Implemented:

* rollback fighter prototype
* two-PC QA benchmark
* ENet multiplayer connection
* Gemini API integration
* move JSON generation
* generated move saving
* generated move injection
* rollback metrics output

In progress:

* checksum validation
* latency stress testing
* cleaner UI
* XR / glasses stretch experiments

---

# Hackathon Summary

SyncStrike demonstrates AI-assisted deterministic multiplayer gameplay.

The core idea:

> Gemini creates the move.
> The rollback engine proves it can run safely.

```
```




