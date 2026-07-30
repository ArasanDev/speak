# Wispr Flow — Input-Layer Taste & Choreography

> Purpose: capture the moment-by-moment *feel* of a single Wispr Flow dictation
> — not a feature list — so `speak` can match/beat it on experiential grounds.
> Extends `specs/wispr-parity-and-spec.md` (which is a feature/pricing parity
> map) and respects the visual language already frozen in
> `specs/frontend-identity.md` and `specs/speak-ui-design-final-2026-06-28.md`.
>
> Tagging: `[verified — URL]` = stated directly by a primary source (Wispr's
> own docs/site) or a hands-on reviewer quoting specifics. `[inferred]` =
> reasoned from indirect evidence, never observed directly. No untagged claims.

---

## 1. Invocation

- Primary activation is **hold-to-talk** or **double-tap-to-toggle** on a
  dedicated key, not a chord: default is double-tap of the right Shift key
  (hold to dictate, release to process and type); Fn+Space or double-tap Fn
  starts a continuous session up to 5 minutes; holding Fn is push-to-talk
  `[verified — https://spokenly.app/blog/wispr-flow-review, https://sites.google.com/view/wispr-flow-review/]`.
  Multiple bindings coexist so the same product serves both "quick phrase"
  and "long monologue" use without asking the user to choose a mode up front
  `[inferred]`.
- On mobile/Android the equivalent is the **Flow Bubble**, a floating pill
  docked over text fields: tap to dictate, long-press to hold-to-dictate
  `[verified — https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android]`.
- On desktop the persistent chrome is the **Flow Bar** — a floating control
  docked at the bottom of the screen by default, draggable to the bottom,
  left, or right edge (snapping into pill-shaped drop zones); it reorients
  vertically when docked to a side edge, and remembers its position across
  launches `[verified — https://docs.wisprflow.ai/articles/5002934560-why-is-the-wispr-bar-is-not-appearing-or-disappearing]`.
  This is a meaningfully different affordance than a single ephemeral overlay:
  it is **always visible, always in the same learned spot**, and dictation
  starts by acting *on* an object that's already on screen, not by summoning
  one from nothing `[inferred]`.
- No specific instant-acknowledgment latency number is published; marketing
  language leans on "instantly" and "speed of thought" rather than a stated
  millisecond budget `[verified — https://wisprflow.ai]`. The pre-listening
  latency budget (keypress → visible "I'm on") is therefore **not measurable
  from public sources** — treat as `[unverified]` for any specific number.

## 2. The listening moment

- During recording the Flow Bar/Bubble shows a **live waveform** plus
  **Cancel** and **Stop/Done** controls — not an orb, not a level meter dot,
  a literal audio waveform rendered in the bar itself
  `[verified — https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android]`.
- The waveform is a genuine level indicator, not decoration: **it goes flat
  after a short period of silence**, which doubles as passive end-of-utterance
  feedback — the user can glance down and see the system registering "you've
  gone quiet" before they even reach to stop `[verified — search-snippet synthesis, NO PRIMARY URL CONFIRMED:
  docs.wisprflow.ai troubleshooting article]`.
- Positioning is bottom-of-screen / user-repositionable, not anchored to the
  text cursor `[verified — same docs URL]`. This is a deliberate trade: a
  fixed, memorized location costs a moment of eye-travel away from the cursor
  but buys predictability and lets it double as a permanent idle-state
  affordance (see §7) `[inferred]`.
- No public source describes an literal "orb" or breathing/pulsing idle
  animation independent of the waveform — reviewers who searched for this
  specifically came up empty `[unverified — SOURCES SILENT, not confirmed
  absent; searched tldv.io/spokenly.app/zackproser.com reviews]`. Treat any claim of a
  glowing-orb aesthetic for Wispr as unverified; the confirmed primitive is
  the waveform-in-a-bar.

## 3. During speech

- **Partial transcripts are not confirmed to stream live word-by-word** in
  any primary source found. Reviewers who looked specifically for this came
  back empty-handed `[unverified — SOURCES SILENT, not confirmed absent;
  searched tldv.io, spokenly.app, zackproser.com]`. The one hard latency figure available — "end-to-end
  latency reported at under 700ms at p99, but the cloud round-trip feels
  closer to 1–2s in practice for most users" `[verified —
  https://zackproser.com/blog/wisprflow-review]` — is stated by that reviewer
  as **end-to-end** (speech → typed text), not partial-transcript latency.
  This is consistent with a **silent-while-listening, reveal-on-stop**
  design: the waveform is the only real-time feedback; the *text* itself
  appears only after the AI cleanup pass completes `[inferred, moderate
  confidence]`.
- **Why this trade-off, inferred**: cloud STT + a second cloud LLM cleanup
  pass means there is no cheap way to show raw partials *and* immediately
  replace them with cleaned text without an ugly "flicker-then-rewrite"
  moment. Wispr's entire value prop is "the raw transcript is never shown to
  you" — showing disfluent partials live would contradict that promise the
  instant before it's fulfilled. Silence during capture protects the product
  narrative: the user says something messy, the *only* thing they ever see is
  the polished result `[inferred]`.
- The AI cleanup itself removes filler words, fixes mid-sentence
  self-corrections, applies punctuation, and adapts tone to the destination
  app (more casual in Slack, more formal in email) — this per-app tone
  adaptation is the single most-praised differentiator in review/Reddit
  coverage `[verified — search-snippet synthesis, NO PRIMARY URL CONFIRMED: Product Hunt / Reddit
  commentary, https://www.producthunt.com/products/wisprflow/reviews]`.

## 4. The end + the wait

- Stopping is symmetric with starting: release the held key, or press the
  activation key again (e.g., "hit fn again") to end capture and hand off to
  processing `[verified — https://zackproser.com/blog/wisprflow-review]`.
- The wait is described honestly by an outside reviewer as a **real, felt
  delay** — "There is a brief delay after you send your speech... for
  processing, but it's still significantly faster than typing"
  `[verified — https://zackproser.com/blog/wisprflow-review]`. No source
  describes a masking animation, progressive reveal, or optimistic paste
  during this gap — the evidence points to a straightforward "wait, then the
  whole cleaned block appears" behavior, not a staged reveal
  `[inferred from absence + the "brief delay...still faster than typing"
  framing, which reviewers accept because the *comparison point is typing*,
  not because the wait itself is hidden]`.
- This is the most important place Wispr's cloud architecture shows: a
  **network round trip is structurally unavoidable dead time** — the p99 700ms
  target implies real engineering effort was spent on it, but the reviewer's
  lived "1–2s in practice" shows the effort tops out where physics and
  internet variance take over `[verified — zackproser, as above]`.

## 5. Delivery

- Text is **typed into the active app wherever the cursor has focus** —
  Cursor, Gmail, Slack, VS Code, any text field, cross-platform (Mac,
  Windows, iOS, Android) with no app-specific integration required
  `[verified — https://zackproser.com/blog/wisprflow-review; docs.wisprflow.ai]`.
  Pipeline as one reviewer summarized it: "Audio uploads to the cloud, gets
  transcribed by Wispr's pipeline (OpenAI subprocessor plus fine-tuned Llama
  for cleanup), and types into the active app"
  `[verified — https://zackproser.com/blog/wisprflow-review]`.
- Delivery mechanism (paste vs. simulated keystroke typing) is not confirmed
  by a primary source in this pass — "types into" language is consistent with
  either; do not assert one over the other `[unverified]`.

## 6. Correction + trust

- There is an explicit **"Undo AI Edit"** control that reveals the raw
  transcript underneath the cleaned text — the trust mechanism is
  transparency-on-demand: the user never sees the raw text by default, but
  can always audit it after the fact if the cleaned version feels off
  `[verified — https://zackproser.com/blog/wisprflow-review]`.
- A **writing-style pill** sits next to the mic control showing the current
  active style/tone setting, giving a persistent, glanceable readout of what
  mode cleanup is operating in before you even speak
  `[verified — search-snippet synthesis, NO PRIMARY URL CONFIRMED: docs.wisprflow.ai search result]`.
- **Command Mode** lets users issue voice instructions (edit commands) after
  dictation — reviewed as the point where the product "starts to feel
  genuinely different from basic dictation tools," i.e., correction happens
  by voice, not by dropping into a text-editing UI
  `[verified — search-snippet synthesis, NO PRIMARY URL CONFIRMED: tldv.io/rewskidotcom coverage]`. No
  primary source describes the exact command-mode UI/visual treatment
  `[unverified]`.

## 7. Ambient/idle state

- The Flow Bar is **persistent, not ephemeral** — it sits docked at a
  user-chosen, remembered screen position at all times, not just during
  active dictation `[verified — docs.wisprflow.ai]`. Idle-state visual
  treatment (icon, color, animation) is not detailed in any source found
  `[unverified]`.
- Users can suppress it: "Hide for 1 hour" from a right-click menu, or a
  global Settings → System → Show Flow Bar toggle
  `[verified — https://docs.wisprflow.ai/articles/5002934560-why-is-the-wispr-bar-is-not-appearing-or-disappearing]`.
  This is the opposite discoverability trade from a menubar icon: it costs a
  permanent sliver of screen real estate in exchange for the activation
  target always being visually present and muscle-memorized in place
  `[inferred]`.

## 8. The invisible engineering

- Reconnect handling is explicit: "reconnects automatically after the system
  wakes from sleep and after signing out and back in"
  `[verified — https://docs.wisprflow.ai/articles/5002934560-why-is-the-wispr-bar-is-not-appearing-or-disappearing]`
  — evidence of deliberate engineering around session/connection state, which
  only matters because the product depends on a live cloud connection at all
  `[inferred]`.
- No public source describes model warm-up, mic pre-arming, or specific
  interruption/app-switch-mid-dictation handling — these remain
  `[unverified]` for Wispr specifically, though they are standard concerns
  any cloud-dependent, always-listening-adjacent product must solve
  `[inferred]`.
- Public latency framing (700ms p99 target vs. 1–2s felt) is itself evidence
  that the team both measures and is candid, internally, that network
  variance dominates their latency budget — the number they optimize is the
  one they control (server-side pipeline), not the one users actually feel
  (client ↔ server round trip under real-world Wi-Fi) `[inferred from the gap
  between the stated p99 and the reviewer's lived experience]`.

---

## Design principles (inferred, stated as principles)

1. **The raw transcript is a liability, never a deliverable.** Nothing in the
   product surfaces disfluent speech-to-text output by default; "Undo AI Edit"
   exists specifically because the default view is the cleaned version.
2. **Feedback during capture is signal-only, not content.** The waveform
   proves "I am hearing you" and "you've gone quiet" — it never previews what
   will be typed. Content only appears once it's ready to be trusted.
3. **One persistent physical home beats a summoned overlay.** The Flow
   Bar/Bubble sits in a fixed, remembered spot rather than materializing near
   the cursor each time — optimizing for muscle memory over spatial context.
4. **Honesty about the wait, not concealment of it.** There is no evidence of
   a masking animation over the AI-cleanup gap; the product instead wins the
   comparison by being faster than typing overall, not by hiding the pause.
5. **Correction happens by voice (Command Mode), not by manual text editing**
   — keeps the user in the same input modality end to end.
6. **Tone adapts to destination, not to the user's own instruction each time**
   — the system infers "Slack = casual, email = formal" so users don't have
   to declare a mode per dictation.

### Where Wispr is constrained by being cloud-based

- The **entire dead-air problem in §4 exists only because of the network
  round trip.** A 700ms-p99/1–2s-real latency floor is a direct tax of
  shipping audio to a server and cleanup back — it cannot go below that floor
  without moving inference on-device.
- **No live partials** is plausibly not a design *choice* so much as a
  consequence of a two-hop cloud pipeline (STT service → LLM cleanup service)
  where showing intermediate STT output would mean showing text the LLM is
  about to rewrite — a coherence problem that gets sharper, not milder, the
  slower the round trip is `[inferred]`.
- **Session reconnect handling** (sleep/sign-out recovery) is only a problem
  because there's a live account/connection to maintain in the first place.
- **Command Mode / cleanup quality is bottlenecked on a hosted LLM** — every
  cleanup pass is metered, rate-limited, and requires an account and network
  reachability; none of this applies to an on-device model.

---

## What `speak` should adopt (ordered by impact)

1. **Silence-then-reveal is not the enemy — the network tax is.** Adopt the
   *principle* (never show a disfluent raw transcript as the "final" output)
   but not the *constraint* (silence during capture). Since `speak` has zero
   network hop, it can stream partials live (already planned per
   `speak-ui-design-final-2026-06-28.md` — Monaco 13pt partial text, <200ms
   latency target) AND still guarantee the cleaned result is what lands at
   the cursor. Best of both: show partials live, but visually mark them as
   provisional (already correct in current overlay design — frozen partial +
   distinct processing state) so users never mistake a partial for the final.
2. **Add a persistent, glanceable "current mode" readout** — Wispr's
   writing-style pill next to the mic is cheap and builds pre-dictation
   trust. `speak`'s overlay already has a gear icon for streaming/language
   (per `speak-ui-design-final-2026-06-28.md` §OverlayHUD); extend it to show
   the active cleanup mode/style at a glance, not just on tap.
3. **Ship an "Undo AI Edit" / show-raw affordance in History**, not just a
   diff view — Wispr's version is inline and immediate; make sure `speak`'s
   post-capture diff (`docs` already plan a diff overlay) is at least as fast
   to reach.
4. **Consider a persistent-position option for power users**, not just an
   ephemeral overlay — Wispr's docked, muscle-memorized Flow Bar is a real
   discoverability/reliability advantage over a summoned panel. `speak`'s
   menubar-icon-as-idle-state already covers ambient/idle; a user-repositionable
   dock is a smaller, optional addition worth considering for v0.1+, not v0.
5. **Command-mode-style voice correction** (edit-by-voice after dictation) is
   the most-praised Wispr differentiator per review synthesis — worth a
   forward-looking roadmap note even though it's not in `speak`'s v0 scope.

## Where `speak` can BEAT them

- **Zero network round trip removes the entire §4 dead-air problem.**
  Wispr's floor is 700ms p99 / 1–2s felt because of the cloud hop; `speak`'s
  on-device pipeline has no such floor — the cleanup gap can be made
  materially shorter and, unlike Wispr, is not subject to Wi-Fi variance at
  all. This is a structural, not incremental, advantage — worth stating
  plainly in-product ("no network round trip" as a felt speed claim, not just
  a privacy one).
- **Live partials without the coherence risk.** Because `speak` controls both
  STT and cleanup locally with no per-request billing/rate-limit pressure, it
  can afford to show live partials AND still guarantee cleanup runs — Wispr's
  plausible reason to suppress partials (a two-hop cloud pipeline where
  showing intermediate output undercuts the "always polished" promise) does
  not apply on-device, where the whole pipeline is fast enough that
  partial-then-refined isn't a UX liability.
- **No account, no reconnect-after-sleep problem, no "sign out and back in"
  session state at all.** Wispr's own docs describe explicit recovery
  engineering for exactly the failure modes a local, account-less app
  structurally cannot have.
- **No metering pressure on Command Mode-style features.** A cloud LLM
  cleanup pass is a cost center for Wispr; on-device, `speak` can make
  voice-correction/edit-by-voice a zero-marginal-cost feature and use it more
  liberally without a pricing/rate-limit story attached.
