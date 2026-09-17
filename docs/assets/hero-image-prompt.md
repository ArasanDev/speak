# Image generation prompts — speak

> Prompts for every image the repo needs: README hero, HUD product shot,
> GitHub social preview, done-state variant, app icon. Each prompt is
> copy-paste ready; model-specific variants at the bottom.
>
> **Grounding note:** `img/speak-overlay-ui.png` is a screenshot of the *old*
> capsule HUD (round end caps, dotted dividers) — **stale, do not use as a
> visual reference**. The shipped panel is described in "Panel anatomy" below;
> generate to that, or better: screenshot the real thing (see Option B).

---

## Panel anatomy (what the real HUD looks like — feed this to the model)

- **Silhouette:** near-rectangle — a wide rectangle with *slightly* rounded
  corners (~14 pt continuous radius on a ~640×76 pt panel). Flat top and
  bottom edges. **Not** a capsule, not a pill, no circular ends.
- **Surface:** dark frosted glass (vibrancy), ink `#16181D`, with a faint
  phase-colored wash. One thin hairline border, mica gray.
- **Leading slot (left):** a voice animation — five thin vertical bars like a
  VU meter, warm amber `#FFB25A` while listening.
- **Header line:** small caps text `LISTENING · 0:12` — phase label + inline
  timer, dim bone `#E9E6E0` at ~60%.
- **Transcript lane:** one or two lines of faint partial-transcript text
  beneath the header.
- **Tally dot:** one tiny coral-red dot `#FF5C49` — the ON AIR lamp — only
  while the mic is capturing.
- **Vibe:** broadcast/studio instrument (VU meter, tally light), never a
  chat bubble, never a card with buttons.

## Palette anchors

| Role | Hex | Use in images |
|---|---|---|
| ink | `#16181D` | panel surface, scene shadows |
| ink2 | `#1F232B` | raised elements |
| bone | `#E9E6E0` | primary text/glyphs |
| mica | `#8A8F98` | hairlines, secondary text |
| humanAmber | `#FFB25A` | waveform bars — the human is speaking |
| onAir | `#FF5C49` | tally dot only — mic is capturing |
| agentViolet | `#9D8CFF` | agent channel — reserve for agent-state images |
| delivered | `#5FBF8F` | checkmark/success only — terminal states |

---

## Prompt 1 — README hero (`img/speak-hero.png`, 1440×720)

```
A photorealistic wide shot of a Mac desktop at dusk: a muted near-black
desktop (#16181D) with a faintly blurred dark code editor window in the deep
background, bokeh-soft. Floating at bottom-center, a small recording HUD: a
near-rectangular dark frosted-glass panel, ~8:1 aspect, with only slightly
rounded corners (flat edges, micro-radius) and a thin gray hairline border.
Inside the panel on the left, five thin vertical amber waveform bars
(#FFB25A) at varied heights like a live VU meter; beside them small dim
monospaced caps text "LISTENING · 0:12" and one faint line of transcript
text. A single tiny coral-red tally dot (#FF5C49) glows on the panel like an
ON AIR lamp. Along the top screen edge, a macOS menubar with a small waveform
icon among standard menubar glyphs. Calm, minimal, broadcast-studio
instrument aesthetic, soft ambient light, shallow depth of field, no clutter,
no people, no logos. High-end product photography, 16:9.
```

## Prompt 2 — HUD product shot (isolated, `img/speak-hud-product.png`, 1600×900)

```
Studio product render of a floating macOS HUD panel on a seamless dark ink
backdrop (#16181D) with a soft radial vignette. The panel is a wide
near-rectangle of dark frosted glass, only slightly rounded corners, thin
hairline edge — floating with a subtle soft shadow beneath, slight
three-quarter perspective. Inside: five amber VU bars (#FFB25A) on the left,
dim monospaced caps text "LISTENING · 0:12", one faint transcript line, and
a tiny coral-red tally dot (#FF5C49). Clean, instrument-grade, museum-product
lighting, crisp on the panel with gentle glow falloff, no other objects.
```

## Prompt 3 — GitHub social preview (`img/speak-social.png`, 1280×640)

```
A minimal dark social card, ink background (#16181D). Centered composition:
the word "speak" in large clean lowercase sans-serif, bone white (#E9E6E0),
with the tagline "your voice is the new keyboard" in smaller dim gray beneath.
Below the text, the small near-rectangular frosted-glass HUD panel with five
amber VU bars (#FFB25A) and a tiny coral tally dot (#FF5C49), floating with a
soft shadow. Generous negative space, flat minimal design, no photographs,
no people. 2:1 social card.
```

## Prompt 4 — Done-state variant (B-side for docs/blog)

Same as Prompt 1 or 2, but the leading slot shows a small green checkmark
(`#5FBF8F`) instead of bars, the header reads `PASTED`, and no tally dot
(the mic is closed — the tally only exists while capturing).

## Prompt 5 — App icon concept (optional exploration)

```
A macOS app icon: a rounded-rectangle dark ink tile (#16181D) containing five
thin vertical amber bars (#FFB25A) of different heights — a minimal VU meter
— with a tiny coral-red tally dot (#FF5C49) at the top-right corner like an
ON AIR lamp. Flat, minimal, Apple-style icon grid, centered, no text, no
gloss. Front view, 1024×1024.
```

---

## Model-specific variants

**Midjourney v6+** — append to any prompt above:

```
--ar 16:9 --style raw --no capsule, pill, mascot, face, clouds, rainbow, neon
```

(For prompt 3 use `--ar 2:1`; prompt 5 `--ar 1:1`. MJ ignores hex values
loosely — the color names "warm amber" and "coral red" carry the intent.)

**DALL·E 3 / GPT-image** — use the prompts verbatim, but spell colors as
names ("warm amber", "soft coral red") — it ignores hex codes. If it renders
a pill anyway, add: *"the panel is almost a plain rectangle — imagine a
rectangle whose corners were sanded only slightly."*

**SDXL / Flux (with negative-prompt field)** — main prompt verbatim; negative:

```
capsule, pill shape, rounded ends, gradient border, neon glow, RGB lighting,
mascot, face, eyes, cartoon, watermark, logo, paragraph text, people, clouds
```

## Universal negative list

- No capsule/pill — flat edges, micro-radius corners only
- No glowing gradient borders, neon, or RGB gamer lighting
- No mascot faces, eyes, characters, or "Clippy energy"
- No cloud/upload/Wi-Fi symbols — the product is 100% local
- No long text — image models mangle paragraphs; only `LISTENING · 0:12` or `PASTED`

## Failure → fix matrix

| If the output… | Change |
|---|---|
| Panel comes out as a pill/capsule | Add "imagine a rectangle whose corners were sanded only slightly"; drop the word "rounded" entirely |
| Mangled/gibberish text | Remove all text from the prompt; add the header in post (Figma/Sketch) — text is 20 pt, models can't do it |
| Too much glow/neon | Add "matte frosted glass, no bloom"; remove "glowing" — say "lit amber bars" |
| Looks like a chat bubble | Remove "floating"; add "broadcast tally instrument, VU meter" |
| Busy desktop behind | "empty desktop, single blurred window, heavy vignette" |

---

## Option B — capture the real HUD instead (recommended for accuracy)

Generated images can *suggest* the product; only a screenshot *is* the
product. The honest path for the README hero:

```bash
make build
open build/DerivedData/Build/Products/Debug/Speak.app --args --debug-open overlay-demo
# then Cmd+Shift+4 → Space → click the panel; crop to taste
# variants: overlay-demo-processing | overlay-demo-done | overlay-demo-error
```

Composite the real HUD PNG over a generated desktop backdrop if you want the
"in situ" look with pixel-accurate UI — best of both: real panel, styled scene.
