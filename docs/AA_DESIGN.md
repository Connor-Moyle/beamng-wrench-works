# Anti-aliasing package: findings and plan (BeamNG 0.39)

Game source checked: `I:\SteamLibrary\steamapps\common\BeamNG.drive` (lua/, shaders/, Bin64 strings).

## 1. What the engine gives a mod

| Need | Found | Verdict |
|---|---|---|
| Velocity / motion vectors | Named render target `#VelocityBuffer` (used as `texture 0` of `AL_VelocityVisualize` in `lua/ge/client/lighting/advanced/lightViz.lua:183`). Written by material shaders (`MFT_FlexMeshPropVelocity`, `defaultMat.hlsl:505`, camera-relative reprojection incl. vehicle node motion). The game's own GTAO upsample (`postFx/gtao/gtao_upsample.cs.hlsl:28,98`) and motion blur (`postFx/motionBlur/motion_blur.hlsl`) read it as `float2`, "last_uv - cur_uv". | **Usable from a PostEffect** (`setField("texture", n, "#VelocityBuffer")`). To verify in game: it is filled while AA/GTAO/motion blur is on (use `AL_VelocityVisualize` once). |
| Depth | `#prepass[Depth]` / `#prepass[RT0]` (smaa, motionBlur, ssao use them) | Yes |
| Previous-frame matrices as post-fx constants | None exposed to Lua PostEffects (the old `motionBlurP.hlsl` wants `matPrevScreenToWorld` but nothing sets it; `worldToScreenPos0PrevFrame` lives in the material cbuffer only) | Not needed: the velocity buffer already holds the reprojection |
| Projection jitter (sub-pixel camera offset) | None. `jitter` appears only in the cloud renderer's own TAAU (`clouds/cloudVrt*.hlsl`). No lua API, no setting, no engine string `TemporalAA/TAAU/DLSS/FSR/renderScale/dynamicResolution` in `BeamNG.drive.x64.exe`. | **Real TAA/TSR is impossible from a mod** (no jitter = no extra samples to accumulate). |
| History buffer | Named targets (`#name`) persist between frames; a second PostEffect can copy back buffer to `#slrrHist` (ping-pong), read next frame. | Feasible, to verify in game |
| Render scale / supersampling | Only `superSampling` in the screenshot/photo-mode capture (tiled, offline). `GraphicAntialias` x1/x2/x4 values exist in `graphic.lua:884` but are not MSAA of the scene (deferred renderer). `uiUpscaling` is UI only. | **No live 3D supersampling from a mod.** |
| SMAA temporal hook | `SMAA.h` has `SMAA_REPROJECTION` and `smaa_NeighborhoodBlendingP.hlsl:12` already passes `velocityTex`; the game never enables it (no 4th sampler in `smaa.lua`). | Our own neighborhood shader could use it |

## 2. Options (what we can build)

Spatial (single frame):
1. **FXAA** (game) and **SMAA High** (game): unchanged, always restorable.
2. **SMAA Ultra** (done in cb45ca1): own copies of edge+weight shaders, Ultra preset, colour edges. Next: depth **predication** (`SMAA_PREDICATION`, needs `#prepass[Depth]` as a 2nd texture of the edge effect) to catch geometry edges colour misses and drop texture noise edges.
3. **FXAA 3.11 quality** (own copy of `fxaa/Fxaa3_11.h`, preset 39, subpixel 0.75): cheap, softer, catches sub-pixel shimmer SMAA cannot.
4. **CMAA2**: skipped; same class as SMAA, big compute port, no gain over Ultra+temporal.

Temporal (the shimmer fix), without jitter:
5. **Temporal smoothing "T1x"**: after the spatial AA, one PostEffect: reproject history with `#VelocityBuffer`, clamp history to the 3x3 neighbourhood of the current frame (variance clip), blend 8..15 % current weight, reject on large velocity or depth discontinuity, then copy result to `#slrrHist`. Cuts specular/foliage/wire crawl and edge crawl. Cannot add real detail (no jitter), so it is "temporal denoise", not TAAU. Camera movement itself gives some natural sub-pixel variation. Risk: ghosting on dynamic objects (velocity handles the car), blur when stopped (counter with CAS).
6. Optional later: SMAA T2x-style neighbourhood blend through the `SMAA_REPROJECTION` path.

Sharpening:
7. **CAS** (done): runs last, strength 0..1; the temporal mode wants about 0.5-0.7 to offset its softness.

Shading/specular AA: needs normal-variance roughness filtering inside the game's material shaders. Overriding `shaders/common/material/...` is a core-file replacement (breaks on every game update, huge shader permutation set). Not recommended; the temporal option is the post-fx substitute.

Real supersampling alternative (no code): NVIDIA DSR 1.78x/2.25x on the 3080 Ti, then pick 2560x1440 in game. The driver downsamples with a smooth filter. Put in README as the "best quality" tip; combine with SMAA High or Ultra.

## 3. Settings (Graphics group, all live)

- Mode: **Game's own** (default, touches nothing) / FXAA 3.11 HQ / SMAA Ultra / SMAA Ultra + Temporal / FXAA HQ + Temporal
- Temporal strength: 0.05..0.3 (default 0.12)
- Sharpening: Off / strength 0..1 (default 0.4)
- Presets: Balanced (Ultra, sharpen 0.4), Smooth (Ultra+Temporal 0.12, sharpen 0.6), Max (Ultra+Temporal 0.08 + DSR tip)
Restore rule: every mode remembers the game's own `shader` field of the effect it replaces and the game's FXAA/SMAA enabled state (as `graphic.lua` sets them), and puts exactly that back on "Game's own", on level end and on mod unload. Tick already follows the player changing AA elsewhere.

## 4. Build order

1. Test cb45ca1 as is (steps below): shader compile, Ultra visible, CAS visible, restore.
2. Depth predication in the Ultra edge effect.
3. Velocity-buffer check, then temporal resolve + history copy (new shaders `slrr_taa*.hlsl`).
4. FXAA 3.11 HQ copy.
5. Settings UI + presets, graphics_test.js additions, README/CHANGELOG.

## 5. Risks

- Shader compile errors only show in game (log lines `slrr_graphics`, `shader`, `hlsl`). One small step at a time.
- `#VelocityBuffer` may be empty when GTAO/motion blur are off: temporal mode would then check it and refuse (note in status) or enable the buffer's producer.
- Temporal history after level change/resize: reset on `onLevelEnd` and when the target size changes.
- Ghosting on the car interior/dash: rely on the game's velocity for the car; clamp strength.

## 6. Round 2: foliage, the game's options page, more edge quality

Findings (game files, 0.39):
- Options page: the Vue page loads `/ui/ui-vue/src/modules/options/runtime/layout.json` at run time (user folder copy wins over the game's; `ui_options.saveLayout` writes it). Items are plain data: `setting` = a key of the game's settings values, `options: [{value,label}]` for choices, `min/max/step` for sliders. UI mod slots exist only for main menu and vehicle config, none for Options. So the controls are a group inserted into the Graphics category after the anti-aliasing type, written at start into the user folder from the game's own file (re-made when the game's file changes).
- Unknown setting keys survive in the game's settings (saved, loaded, only a log warning), the game calls `onSettingsChanged` on extensions after each save: that is the hook.
- Foliage: wind animation moves vertices in the vertex shader; the velocity buffer has the camera and rigid motion, but a leaf swaying in the wind is a "static" pixel that shows a different surface. Counter in the temporal pass: depth range around the pixel (thin geometry cuts the history), history depth vs now (another surface rejects it), and a colour-distance penalty after the clamp. Tunables: `require('slrr/graphics').tune{guard=0.8, gamma=1}`.
- Texture LOD bias: only a sampler-state field (`mipLODBias`) of material state blocks; no global setting reachable from Lua. MSAA / alpha-to-coverage: no setting or Lua call (only a Vulkan dynamic-state string in the exe). Not possible.
- The game's `edgeAA` (EdgeDetectPostEffect + EdgeAAPostEffect, depth and normal edges, 9-tap blur): exists but left off; offered as an optional pass.
- Specular shimmer: needs normal-variance filtering in the material shaders (core file override). The temporal pass is the post-fx substitute; a normal-variance-driven history boost (#prepass[RT0] holds normals and roughness) is the next idea if shimmer on paint and wet roads stays.

## 7. Look: a light colour grade and vignette (design, before building)

Asked for: an optional, subtle "Look" next to the anti-aliasing: filmic contrast, saturation, warm/cool, a light vignette, 3 presets (Natural, Cinematic, Vivid); off by default, live, and the game's own state restored exactly.

Findings (game files, 0.39):
- The game has a grade of its own: the HDR combine pass (`shaders/common/postFx/hdr/finalPassCombineP.hlsl`) applies tone mapping and a per-channel 1D colour ramp (`colorCorrectionRamp`, `colorCorrectionStrength`). That ramp is per channel only (no saturation, no vignette) and is part of the game's graphics settings, so changing it would have to be put back by hand. Not used.
- The effects that run at `PFXAfterDiffuse` after the game's HDR combine see the finished, display-referred picture (the anti-aliasing and our sharpeners already work there). One more full-screen effect at a lower priority (after the sharpeners) can grade that picture and is removed by disabling it: nothing of the game's is touched, so "restore exactly" is the effect being off.
- The UI is drawn by the browser layer on top, so a vignette/grade never touches menus or the HUD.
- Sharper distant detail: not reachable (texture LOD bias is a material sampler-state field only, see round 2). The sharpeners already give the local-contrast part of it.

Plan: one pass, shader `slrr_look*.hlsl`, in display space on the finished picture, in this order: split toning (teal shadows, warm highlights), warmth (cool to warm), filmic contrast (a smoothstep S-curve blended in), saturation, vignette (aspect-correct radial, smooth), then a 1-LSB triangular dither so the 8-bit picture does not band. Every control at its neutral value does nothing, and when all are neutral the effect is disabled (zero cost).
- Settings (game settings keys `slrrLook*`, group "Wrench Works: look" in Options > Graphics, marker `look-v1`, own module `slrr/look.lua`): Preset (Off / Natural / Cinematic / Vivid / Custom), Contrast 0..1, Saturation -0.5..0.5, Warmth -1..1, Colour split 0..1, Vignette 0..1.
- Presets: Natural (contrast 0.15, saturation +0.05, warmth +0.10, vignette 0.15), Cinematic (contrast 0.35, saturation -0.05, warmth +0.10, split 0.5, vignette 0.35), Vivid (contrast 0.25, saturation +0.25, vignette 0.10).
- Same mechanics as the anti-aliasing options: a preset change fills the others, changing any one makes it Custom (or the preset it now equals); `tick` re-applies every 2 s and after a level load, `onModDeactivated`/unload switches it off.
- Test: `tools/look_test.js` (plan, presets, neutral = off, option reading, group data); frame cost and before/after shots through the tester.
