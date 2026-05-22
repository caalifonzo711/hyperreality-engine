# SyncStrike — Gemini Rollback Fighter

## Google I/O Build With AI Hackathon Edition

Built on top of the Hyperreality Rollback Engine. 

A rollback-synchronized multiplayer fighting game where Gemini generates deterministic-compatible move data in real time.

This project explores how LLM-generated content can safely integrate into rollback multiplayer systems without breaking synchronization.

---

# 🚀 What Makes This Different

Most AI projects are:

* asynchronous
* chat-based
* productivity-focused
* disconnected from real-time systems

This project demonstrates:

```text
Prompt
↓
Gemini
↓
Structured Move JSON
↓
Rollback Fighter
↓
Deterministic Multiplayer Execution
```

The generated move data is loaded directly into a rollback-safe combat state machine.

---

# 🎮 Current Demo

The current hackathon demo supports:

✅ Gemini-generated move configs
✅ rollback multiplayer architecture
✅ deterministic combat simulation
✅ live JSON generation + saving
✅ generated move injection into gameplay
✅ synchronized rollback fighter prototype

---

# ⚠️ IMPORTANT

This is an experimental hackathon prototype.

The current goal is:

> demonstrating AI-assisted deterministic gameplay systems.

NOT:

* autonomous AI gameplay
* procedural game generation
* replacing simulation authority with LLMs

Gemini only generates structured move configuration data.

Rollback simulation remains authoritative.

---

# 🧠 Core Concept

Most multiplayer games delay player actions to wait for the network.

Rollback works differently:

```text
Input
↓
Immediate Local Response
↓
Predict Missing Remote Input
↓
Receive Delayed Truth
↓
Rollback Old Frames
↓
Replay Forward
↓
Correct Reality
```

Result:

* responsive multiplayer gameplay
* low-latency feel
* synchronized simulation

---

# 🤖 Gemini Integration

Gemini is used as a:

> constrained gameplay configuration generator.

Example prompt:

```text
make a strong kick with:
startup 8
active 4
recovery 15
```

Gemini generates:

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

The move is then:

* saved to JSON
* loaded into the rollback fighter
* injected into the heavy attack timing system

---

# ⚙️ REQUIREMENTS

## Godot

Godot 4.x

## Gemini API Key

You need a Gemini API key from:

[Google AI Studio API Keys](https://aistudio.google.com/app/apikey?utm_source=chatgpt.com)

---

# 🔑 API KEY SETUP

## Windows PowerShell

Run:

```powershell
setx GEMINI_API_KEY "YOUR_API_KEY_HERE"
```

IMPORTANT:
After running this:

* close Godot completely
* reopen Godot

The project loads the key from:

```gdscript
OS.get_environment("GEMINI_API_KEY")
```

---

# ▶️ HOW TO RUN

## 1. Clone Repo

```bash
git clone https://github.com/caalifonzo711/hyperreality-engine.git
```

Open in Godot 4.x. 

---

# ▶️ Main Fighter Scene

Open:

```text
FighterArena.tscn
```

Run:

```text
F6
```

---

# 🧪 Gemini Panel

The Gemini UI panel is:

```text
addons/gemini_integration/tools/GeminiConfigGeneratorPanel.tscn
```

The panel should already exist inside the fighter scene for hackathon demos.

---

# 🎮 CONTROLS

Check:

```text
Project Settings → Input Map
```

Current important actions:

```text
atk_l = light attack
atk_h = heavy attack
```

Heavy attack is currently overridden by Gemini-generated move data.

---

# 🧠 HOW TO USE THE GEMINI DEMO

## Step 1 — Enter Prompt

Type something like:

```text
make a super fast heavy kick
startup 1
active 10
recovery 5
```

OR:

```text
make a ridiculously slow heavy attack
startup 60
active 20
recovery 60
```

---

# Step 2 — Click Generate

The LEFT button:

```text
Generate
```

calls Gemini.

Gemini returns structured move JSON.

---

# Step 3 — Click Save

The RIGHT button:

```text
Save
```

does ALL of the following:

✅ saves JSON to:

```text
games/rollback_fighter/moves/
```

✅ reloads move data

✅ injects generated move into live PlayerState nodes

✅ updates heavy attack timing live

---

# ✅ SUCCESS CONDITION

If successful, console should print:

```text
[GeminiPanel] Applied generated move to 2 PlayerState node(s)
```

That means:

* Gemini generated valid move data
* JSON saved successfully
* move injected into gameplay

---

# 🎮 TESTING THE GENERATED MOVE

Press:

```text
atk_h
```

to trigger the Gemini-generated heavy attack.

## Example

If startup = 60:

* heavy attack becomes VERY slow

If startup = 1:

* heavy attack becomes nearly instant

This confirms:

> Gemini-generated move timing is controlling live gameplay.

---

# 🔄 Rollback Architecture

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

The rollback layer is intentionally separated from:

* Gemini
* networking transport
* rendering

This preserves deterministic simulation integrity. 

---

# 🧠 Current Architecture

```text
Gemini Prompt
↓
GeminiClient
↓
Gemini JSON
↓
ConfigFactory
↓
Move JSON
↓
PlayerState
↓
Rollback Simulation
↓
CombatSystem
↓
Rendering
```

---

# 🎯 Hackathon Goal

Demonstrate:

> AI-assisted deterministic multiplayer gameplay systems.

The key technical challenge:

* constraining AI outputs
* preserving rollback synchronization
* maintaining deterministic replay safety

---

# 🧪 Recommended Demo Flow

## Demo 1 — Fast Move

Generate:

```text
startup 1
```

Show instant heavy attack.

---

## Demo 2 — Slow Move

Generate:

```text
startup 60
```

Show extremely delayed heavy attack.

---

## Demo 3 — Multiplayer

Run rollback multiplayer session.

Show:

* generated move still synchronizes
* rollback still functions
* deterministic replay preserved

---

# 📌 Current Status

## Implemented

✅ rollback replay
✅ deterministic simulation
✅ synchronized multiplayer prototype
✅ Gemini move generation
✅ JSON save pipeline
✅ live gameplay injection
✅ rollback-safe combat prototype

---

## In Progress

⚠️ higher latency testing
⚠️ multiplayer polish
⚠️ XR experiments
⚠️ advanced move balancing tools

---

# 🧠 Philosophy

Small deterministic systems that scale into anything.

Current priorities:

* rollback correctness
* deterministic simulation
* transport-independent architecture
* understandable systems
* rapid iteration

---

# Built By

Alonso Rojas

LinkedIn:
[Alonso Rojas LinkedIn](https://www.linkedin.com/in/alonso-rojas-617546126/?utm_source=chatgpt.com)



