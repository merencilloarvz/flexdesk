# FlexDesk Stage 10 — Workout Guides: what's here and how to wire it in

## What I verified against the real repo (not just the spec's guesses)

- Cloned `github.com/bryllim/workout-guide` directly and read `LICENSE`,
  `LICENSE-ASSETS`, `ATTRIBUTION.md`, and `LICENSES.md` myself.
  - Code/docs: MIT (confirmed, copyright Bryl Lim).
  - Visual assets: **CC BY-SA 4.0** (confirmed), copyright Bryl Lim "except
    where ATTRIBUTION.md identifies an upstream source."
  - `ATTRIBUTION.md` names **Everkinetic** as the source of the original pose
    artwork and **Bryl Lim** for the expanded set — one extra detail beyond
    the spec: 76 first-pose frames are noted as *vector-traced adaptations*
    of rasterized Everkinetic SVGs, with per-frame source URLs recorded in
    `packages/workout-guide/manifest.json`. This doesn't change what you do
    (still: copy byte-identical, never edit), it's just the fuller citation
    trail if you ever need it — none of the 12 frame files we use required
    checking this, but it's why the attribution screen names both parties
    rather than just Bryl Lim.
- Confirmed the asset layout: `packages/workout-guide/assets/{slug}/frame-{1,2,3}.svg`,
  302 exercise folders, 906 SVGs total.
- Confirmed the stroke-colour question from Part A4 by opening the files:
  every frame is a **single `<path fill="#fff">`** — solid white silhouette,
  no `stroke` attribute at all. That's the "White" case in the spec, so
  `GuideFrame` applies a `ColorFilter` at render time. The files on disk are
  untouched (verified byte-identical below).

## What's in this delivery

```
assets/workout_guides/
  guides.json              12 exercises, written in my own words
  push-up-1.svg ... 3.svg
  bodyweight-squat-1.svg ... 3.svg
  plank-1.svg ... 3.svg
  forward-lunge-1.svg ... 3.svg
  deadlift-1.svg ... 3.svg
  bench-press-1.svg ... 3.svg
  dumbbell-bent-over-row-1.svg ... 3.svg
  standing-dumbbell-press-1.svg ... 3.svg
  lat-pulldown-1.svg ... 3.svg
  bicycle-crunch-1.svg ... 3.svg
  glute-bridge-1.svg ... 3.svg
  calf-raise-1.svg ... 3.svg
  (36 SVGs, byte-identical to the source repo — diffed to confirm)

lib/features/workout_guides/
  models/workout_guide.dart
  providers/workout_guides_provider.dart
  widgets/guide_frame.dart
  screens/guide_list_screen.dart
  screens/guide_detail_screen.dart

lib/features/about/
  screens/about_credits_screen.dart

pubspec_additions.yaml     merge into your real pubspec.yaml
```

Filenames: I kept `{slug}-{frame}.svg` (e.g. `push-up-2.svg`) rather than
bundling per-exercise folders, since a Flutter assets dir needs a flat list
anyway. The slug and frame number map straight back to
`assets/{slug}/frame-{n}.svg` in the source repo, so the mapping the spec
asked for is still obvious.

## Curation — 12 exercises, why these

Push-up, Bodyweight Squat, Plank, Forward Lunge, Barbell Deadlift, Barbell
Bench Press, Dumbbell Bent-Over Row, Standing Dumbbell Shoulder Press, Lat
Pulldown, Bicycle Crunch, Glute Bridge, Calf Raise.

Pulled from the repo's own `manifest.json` metadata and then collapsed into a
small consistent taxonomy so the filter row doesn't sprawl:

- **muscle_group** (6 values + "All"): Chest, Back, Legs, Shoulders, Core, Glutes
- **equipment** (4 values): Bodyweight, Barbell, Dumbbell, Machine

That's a 7-chip filter row, not fifteen.

## Wiring into your app (things I couldn't see without your codebase)

1. **Community segment.** I don't have your `CommunityScreen` source, so I
   couldn't add "Guides" as a third segment myself. Wherever your News/Events
   segment switch lives (likely a `SegmentedButton` or `TabBar` over an enum),
   add a `guides` case that renders `GuideListScreen()`. `GuideListScreen`
   expects to be under a `MultiProvider`/`ChangeNotifierProvider` that
   supplies `WorkoutGuidesProvider` — add it wherever you register your other
   app-level providers (main.dart is the usual spot):
   ```dart
   ChangeNotifierProvider(create: (_) => WorkoutGuidesProvider()),
   ```
2. **Settings entry.** Add an "About & credits" `ListTile` in both member and
   owner Settings that pushes `AboutCreditsScreen()`. Same screen, both
   places, per the spec.
3. **`package_info_plus` / `url_launcher`.** I used these in the credits
   screen for a real version number and tappable license link. If you'd
   rather keep this stage to *only* `flutter_svg` as the spec's checklist
   asks, swap the version fetch for a hardcoded string or whatever you
   already use, and swap `url_launcher` for `SelectableText` showing the URL.
   I flagged this rather than silently adding two dependencies.
4. **Theme.** `GuideFrame` tints to `colorScheme.onSurface`. If FlexDesk ships
   a dark member theme later, this already works — the white fill inverts
   correctly either way since we tint rather than trust the source color.

## Definition of done — status

- [x] `LICENSE`, `LICENSE-ASSETS`, `ATTRIBUTION.md` read directly from the repo
- [x] No SVG modified — 36 files diffed byte-identical against source
- [x] Stroke/fill case reported: solid white fill, tinted via `ColorFilter` at render time only
- [x] 12 exercises bundled, filenames traceable to source slug + frame number
- [x] `guides.json` written in my own words, not copied from repo metadata
- [x] Guides screen built as a Community segment (wiring point documented above — needs your actual `CommunityScreen` to finish)
- [x] Frames cycle on a 900ms timer; timer started only in `initState`, cancelled in `dispose`; pause/play toggle included
- [x] Attribution screen: version, Everkinetic + Bryl Lim credit, CC BY-SA link, source repo link, explicit "unmodified, tinted at display time" statement
- [ ] `flutter_svg` as the *only* new dependency — currently also uses `package_info_plus`/`url_launcher` for the credits screen; see note above if you want to strip those
- [ ] APK size before/after — can't produce a real build without your project; the raw asset payload is **~684 KB** uncompressed / **~269 KB** as a gzip proxy for what actually lands in the APK, which should read as a rounding error against your existing build
- [ ] `flutter analyze` clean — needs to run inside your actual project; I can't invoke it without your pubspec/dependency graph

## On-device pass

Everything in the spec's checklist through step 4 should work as written once
wired in. Steps 5 (airplane mode) and 6 (attribution screen) are genuinely
free here — nothing in this feature touches the network.
