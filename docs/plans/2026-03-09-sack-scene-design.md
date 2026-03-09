# Sack Scene Design

**Date:** 2026-03-09
**Feature:** Sack pickup scenario — exposure therapy for upper body pain

---

## Purpose

Exposure therapy for patients with upper body pain who fear strenuous daily activities (e.g. lifting groceries). The user physically grips and lifts a virtual sack, demonstrating that the movement can be completed without harm.

---

## Scene Flow

1. **Spawn** — `PlaneDetectionProvider` finds the nearest floor plane (y < 0.3, in front of user). Sack placed on floor with visual-bounds correction so its base sits flush on the surface. Fallback to hardcoded floor position `[0, 0, -0.8]` after 3 seconds if no plane is found.

2. **Idle** — A green orb floats ~15cm above the sack's visual top. Instruction panel reads: *"Bring your right hand to the top of the bag and grip to pick it up."*

3. **Proximity** — When the right wrist comes within 20cm of the orb, the orb scales up slightly (pulse) to signal readiness.

4. **Clench** — Fist detected while hand is in proximity zone. Sack locks to wrist, offset 25cm downward so it hangs naturally at the side.

5. **Carrying** — Orb disappears. Sack tracks wrist every frame.

6. **Payoff** — Encouragement label fades in. `AVSpeechSynthesizer` narrates: *"You did it. Your body carried the weight. Pain anticipated is not always pain caused."* Reset button appears.

---

## Clench Detection

Per hand-tracking frame (right hand only):

1. Use `.middleFingerMetacarpal` world-space position as palm center proxy.
2. Measure distance from each of the 4 fingertips (index, middle, ring, little) to palm center.
3. **Fist condition:** all 4 distances < 0.07m.
4. **Proximity condition:** wrist within 0.20m of orb position.
5. Pickup triggers only when both conditions are true simultaneously.

---

## Green Orb

- `MeshResource.generateSphere(radius: 0.05)`
- `SimpleMaterial(color: UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.7), roughness: 1.0, isMetallic: false)`
- Positioned at sack top + 0.15m after surface snap.
- Pulses (scale 1.0 → 1.3 over 0.3s) when hand enters proximity.
- Hidden on pickup.

---

## ARKit Providers

- `HandTrackingProvider` — right hand joints, every frame
- `PlaneDetectionProvider(alignments: [.horizontal])` — floor detection
- Auth: `.handTracking` + `.worldSensing`
- Session started before concurrent async tasks (per project pattern)

---

## Integration Checklist

- [ ] Add `case sack = "SackScene"` to `AppModel.SceneType`
- [ ] Create `SackSceneView.swift`
- [ ] Register `ImmersiveSpace(id: AppModel.SceneType.sack.rawValue)` in `ThresholdApp.swift`
- [ ] Confirm `Sack.usda` is included in the RealityKitContent bundle

---

## Encouragement Text

> "You did it. Your body carried the weight. Pain anticipated is not always pain caused."

---

## Out of Scope

- Left hand support (deferred)
- Two-handed grip
- Physics-based weight simulation
- Sound effects (can be added later following `PrickSoundPlayer` pattern)
