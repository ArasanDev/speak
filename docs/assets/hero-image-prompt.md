# Hero image prompt — `img/speak-hero.png`

> Generate at **1440×720** (2× for a 720 pt-wide README slot). Save to
> `img/speak-hero.png`. The image should say *"a calm instrument living on a
> Mac desktop"* — not a flashy product render.

## Prompt

```
A clean, photorealistic macOS desktop wallpaper scene at dusk — a muted dark
desktop with a faint code editor window blurred in the deep background. Floating
at bottom-center of the screen, a small recording HUD panel: a near-rectangular
dark frosted-glass panel with very slightly rounded corners, a thin subtle
hairline border. Inside the panel, on the left, five thin vertical waveform
bars glowing a warm amber (#FFB25A) at different heights like a live VU meter,
and next to them small dim monospaced text reading "LISTENING · 0:12" and a
line of faint transcript text. At the top edge of the desktop, a macOS menubar
with a tiny waveform icon lit among standard menubar icons. One tiny
coral-red tally dot (#FF5C49) glows on the panel's edge like an ON AIR lamp.
Calm, minimal, studio-instrument aesthetic — broadcast hardware vibes, dark
ink tones (#16181D), soft ambient light, no clutter, no people, no logos.
Style: high-end product photography meets minimal UI design, 16:9 crop.
```

## Negative prompt / avoid

- No capsule/pill-shaped panel — the HUD is a **near-rectangle** with
  micro-curved corners, not a rounded pill
- No glowing gradient borders or RGB gamer lighting
- No cute mascot faces, eyes, or characters on the panel
- No cloud icons, no Wi-Fi/upload symbols (the product is 100% local)
- No text beyond "LISTENING · 0:12" — AI image models mangle paragraphs

## Palette anchors (from `SpeakColors` / frontend-identity spec)

| Role | Hex | In the image |
|---|---|---|
| ink | `#16181D` | panel surface |
| bone | `#E9E6E0` | dim text |
| humanAmber | `#FFB25A` | the waveform bars — the human is speaking |
| onAir | `#FF5C49` | one small tally dot — mic is capturing |

## Alternates worth generating

1. **Done state** — same scene, bars replaced by a small green
   (`#5FBF8F`) checkmark, header reads "PASTED". For a README "how it works"
   strip or social card B-side.
2. **Square social crop** — 1200×1200 centered on just the HUD panel for
   GitHub social preview (repo Settings → Social preview).
