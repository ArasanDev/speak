---
name: monaco-font-theme
description: "speak's UI typographic theme is Monaco (macOS-native monospace) — user's locked design choice"
metadata: 
  node_type: memory
  type: project
  originSessionId: 857e4436-d57b-483f-815b-a91f16858e8a
---

The user wants **Monaco** as `speak`'s typographic theme — the macOS-native
monospace font — chosen explicitly for its calm, even, easy-on-the-eyes rhythm
("keeps me very calm"). Confirmed 2026-06-21 (dictated as "Mooka Mooho" → Monaco).

**Why:** it's a deliberate aesthetic preference that should feel calming, and it's
native + zero-dependency (fits the Apple-frameworks-only wedge). Matches the
"SF-Mono log-file" direction the competitor research already identified — but the
user picked Monaco specifically over SF Mono/Menlo.

**How to apply:** Monaco for *content + data* (history/dashboard rows, timestamps,
HUD transcript text, keycaps); system UI font for chrome/labels. Define it ONCE as a
design token (e.g. `Font.speakMono`), never hardcode the family string per view.
SwiftUI: `.font(.custom("Monaco", size:))`. Recorded in the Phase-2 design system in
[[acceleration-plan]] (specs/acceleration-plan.md).
