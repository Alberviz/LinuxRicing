# Gargantua Black Hole Implementation Plan

> **For Gemini:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a physically faithful, high-aesthetic Gargantua black hole (based on the general relativity model from *Interstellar*) in the `solarfield.frag` GPU shader, featuring the front equatorial disk crossing over the shadow, lensed dual arches (top and bottom), continuous turbulent plasma texture, and intense incandescent bloom with Material You integration.

**Architecture:** Analytical general relativistic gravitational lensing model in GLSL:
1. `diskBack`: Lensed back-disk emission forming the primary upper arch and secondary lower arch around the photon sphere.
2. `horizon`: Event horizon shadow ($r \le R$) with the ultra-thin, hyper-bright Doppler-beamed photon ring, composited over `diskBack`.
3. `diskFront`: Direct equatorial front disk passing in front of the horizon, seamlessly transitioning to `diskBack` at the outer limbs, composited over `horizon`.
4. High-dynamic-range thermal gradient (incandescent white ISCO core with bloom -> M3 amber -> deep red/smoke) and asymmetric relativistic beaming ($pow(approach, 3.2)$).

**Tech Stack:** GLSL (OpenGL / Vulkan via Qt6 `qsb`), Qt6 Quick / Quickshell ShaderEffect, Caelestia Shell.

---

### Task 1: Setup Dedicated Branch in Worktree

**Files:**
- Worktree: `/home/alberviz/LinuxRicing/.worktrees/sistema-solar-v3`

**Step 1: Check git status and create branch**
Run:
```bash
git checkout -b feat/gargantua-black-hole
```

**Step 2: Verify branch creation**
Run:
```bash
git branch --show-current
```
Expected: `feat/gargantua-black-hole`

---

### Task 2: Implement Gargantua Shader Logic in `solarfield.frag`

**Files:**
- Modify: `configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag:169-385`

**Step 1: Write helper functions for disk emission and dual-arch lensing**
- Implement `sampleDisk(rD, thetaD, time, music, musicProgress, musicPulse, musicBass, musicTreble, musicBurstAge, P, ERR)` returning `vec4(rgb, alpha)`.
- Continuous plasma texture (no periodic harsh `sin()` rings).
- Thermal gradient with white-hot core (`vec3(1.0)`), warm M3 body, and deep red smoky rim.
- Realistic Doppler beaming with `pow(approach, 3.2)` and asymmetric boost.

**Step 2: Implement Front/Back + Dual Arch compositing in `blackHole()`**
- Calculate `diskBack` (top lensed arch and bottom lensed arch).
- Composite `horizon` and `photonRing` over `diskBack`.
- Calculate `diskFront` for the front equatorial half ($Y_{disk} < 0$) with seamless limb blending.
- Composite `diskFront` over `horizon`.

**Step 3: Compile shader to QSB**
Run:
```bash
/usr/lib/qt6/bin/qsb --qt6 -o /home/alberviz/LinuxRicing/.worktrees/sistema-solar-v3/configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag.qsb /home/alberviz/LinuxRicing/.worktrees/sistema-solar-v3/configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag
```
Expected: Compilation succeeds without warnings or errors.

---

### Task 3: Deploy to Quickshell and Reload

**Files:**
- Target: `~/.config/quickshell/caelestia/modules/background/solarsystem/shaders/`

**Step 1: Copy compiled shader and source to live config**
Run:
```bash
cp /home/alberviz/LinuxRicing/.worktrees/sistema-solar-v3/configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag* ~/.config/quickshell/caelestia/modules/background/solarsystem/shaders/
```

**Step 2: Clean restart Quickshell**
Run:
```bash
pkill -9 -x qs; pkill -9 -f quickshell; sleep 2.5; rm -rf ~/.cache/quickshell/qmlcache
qs -c caelestia -n -d 2>&1; sleep 6; pgrep -xc qs
```
Expected: `pgrep -xc qs` returns 1, and Quickshell logs confirm `Configuration Loaded`.

---

### Task 4: Visual Verification and Refinement

**Files:**
- Capture: `/tmp/desktop_gargantua.png`

**Step 1: Capture clean desktop with grim**
Run:
```bash
hyprctl dispatch 'hl.dsp.focus({ workspace = 9 })' && sleep 0.8 && grim -o eDP-2 /tmp/desktop_gargantua.png && hyprctl dispatch 'hl.dsp.focus({ workspace = 3 })'
```

**Step 2: View screenshot with `view_file`**
Inspect the rendered black hole:
- Check that the front disk passes directly in front of the lower half of the black hole shadow.
- Check that the upper arch wraps smoothly over the top.
- Check that the lower arch is visible under the shadow.
- Check that the plasma looks fluid and continuous rather than thin geometric wire rings.
- Check that the Doppler beaming makes the oncoming side noticeably brighter.

**Step 3: Commit the feature**
Run:
```bash
git add configs/quickshell/caelestia/modules/background/solarsystem/shaders/solarfield.frag* docs/plans/
git commit -m "feat(solar-system): implementar agujero negro fiel estilo Gargantua (relatividad general)"
```

---

### Task 5: Merge and Update Log

**Files:**
- Merge back to `feat/sistema-solar-v3`
- Update: `vault/🎯 Hoy.md` (bitácora)

**Step 1: Merge `feat/gargantua-black-hole` into `feat/sistema-solar-v3`**
Run:
```bash
git checkout feat/sistema-solar-v3
git merge feat/gargantua-black-hole
```

**Step 2: Update session log in `vault/🎯 Hoy.md`**
Add session summary line to the top of `📓 Bitácora de sesiones`.
