# Optional XR Fighter Demo

## Purpose

This module is a minimal, optional XR presentation mode for the existing rollback fighter. It does not replace the normal game or introduce an XR-specific simulation.

## What it does

- Reuses the existing `FighterArena` scene and simulation.
- Renders the arena through an 800x450 `SubViewport` onto a world-space `FighterStage` surface.
- Places the stage in front of the viewer when the scene starts or the user explicitly recenters.
- Keeps the stage fixed in world space between recenter operations.
- Supports bounded distance, vertical offset, and display-scale adjustments.
- Uses the generic Godot OpenXR interface when it is available.
- Falls back to `DesktopCamera3D` when OpenXR is unavailable or cannot initialize.
- Requests passthrough only when the active runtime reports Godot's alpha environment blend mode as supported.
- Uses a transparent XR viewport so a supporting compositor can place the stage over passthrough or another external background.

## What it does not do

- No XR-specific combat or input simulation.
- No hand tracking, grabbing, locomotion, spatial menus, or controller redesign.
- No room scanning, scene understanding, or anchors tied to furniture or detected surfaces.
- No independent 3D fighter bodies or rigs.
- No gameplay, rollback, prediction, checksum, networking, hitbox, or commerce changes.

## Architecture

```text
Existing FighterArena
        |
        v
   SubViewport
        |
        v
 FighterStage (world space)
        |
        v
 Viewer sees the same simulation
 through the active camera
```

The tracked viewer and fighter stage are separate world-space branches:

```text
FighterXRDemo
|-- XROrigin3D
|   `-- XRCamera3D
|-- DesktopCamera3D
`-- FighterStage
```

`FighterStage` is never parented to either camera. Head pose changes only the viewpoint. Stage placement samples the active camera once and does not run continuously.

## Launch behavior

The project main scene remains `MainMenu.tscn`, so normal desktop launch is unchanged. Launch `games/rollback_fighter/scenes/FighterXRDemo.tscn` explicitly from the editor or command line to enter the XR demo.

OpenXR is initialized only by `FighterXRDemo`. If OpenXR is missing or initialization fails, the scene selects `DesktopCamera3D` and continues. The XR viewport uses transparency only while this scene is active and restores the root viewport on exit.

Passthrough is a runtime capability, not an assumption. The demo queries Godot's built-in `XRInterface.get_supported_environment_blend_modes()` and requests `XR_ENV_BLEND_MODE_ALPHA_BLEND` only when advertised by the active runtime. Failure leaves the demo running with transparent/empty XR background behavior. Unsupported runtimes report `Unsupported`; desktop fallback reports `N/A`.

## Development controls

These controls are handled only by the XR wrapper in debug builds and do not modify the project gameplay InputMap:

- `R`: recenter the stage from the current viewer pose.
- `[` / `]`: decrease/increase distance by 0.25m.
- `Page Down` / `Page Up`: lower/raise the stage by 0.10m.
- `-` / `+`: decrease/increase display scale by 0.10x.
- `0`: restore 2.0m distance, -0.45m vertical offset, and 1.0x scale, then recenter.
- `P`: toggle passthrough when the runtime reports support; otherwise it safely does nothing.

The debug overlay reports XR mode, passthrough status, world-anchor status, and current presentation values.

## Headset or OpenXR emulator smoke test

Use any standards-compatible OpenXR headset, emulator, or runtime; no vendor-specific runtime is required by this module.

1. Launch `FighterXRDemo.tscn`.
2. Confirm the overlay reports `XR Mode: OpenXR`.
3. Confirm both fighters appear in front of the viewer and continue simulating.
4. Turn your head away and confirm the stage does not rotate or follow the view.
5. Turn back and confirm the stage remains at its original world position.
6. Move or lean your head and confirm only the viewpoint changes.
7. Press `R` and confirm the stage relocates in front of the current viewer pose.
8. Adjust distance, height, and scale with the documented controls.
9. If the overlay reports passthrough support, press `P` to enable or disable it.
10. Confirm only the background changes and the fighter simulation continues unchanged.
11. Exit the demo and launch the project normally.
12. Confirm the normal desktop fighter path remains unchanged.

Do not report passthrough as working unless the runtime reports support and the compositor visibly supplies the background.

## Desktop fallback test

1. Launch `FighterXRDemo.tscn` without an active OpenXR runtime.
2. Confirm the overlay reports `XR Mode: Desktop fallback` and `Passthrough: N/A`.
3. Confirm the fight renders and continues simulating.
4. Exercise recenter, distance, height, scale, and reset controls.
5. Confirm `P` has no effect and does not interrupt the fight.
6. To test anchoring, change `DesktopCamera3D` position or yaw through the editor Remote inspector and confirm the stage does not follow.
7. Press `R` and confirm the stage moves in front of the new camera pose.
8. Launch the project normally and confirm `MainMenu.tscn` remains the default path.

## Current limitations

- Actual passthrough availability and composition depend entirely on the selected OpenXR runtime.
- There is no dedicated desktop free-fly camera controller; the editor Remote inspector can simulate camera pose changes.
- Stage anchoring is process-local world placement, not a persistent spatial anchor.
- The arena remains a single flat world-space surface rather than separate 3D fighter bodies.
