# Streaming Raw Text Feature — Architectural Review

**Status:** DESIGN CONFLICT IDENTIFIED  
**Date:** 2026-06-28  
**Reviewer Role:** Architecture validator for the `speak` team

---

## Summary (read this first)

The stated requirement — **"raw text streams to cursor in real-time, then cleaned text replaces it after stop"** — presents a **critical architectural collision with v0's paste design**. The "replace" phase cannot be implemented safely under v0 constraints. This review surfaces that conflict, recommends a safe default, documents the streaming path if the human chooses to proceed, and provides exact API shapes for either direction.

**Recommendation:** Default to the **current v0 design** (live overlay shows partials; target app receives one final clean paste at stop). If streaming raw-to-cursor is essential, it requires a **human design decision** and a **behavior-contract change** documented below in Q4.

---

## THE CRITICAL FINDING: Why Streaming Raw Then Replacing Doesn't Work (v0 constraints)

### 1. **The "replace" operation has no safe primitive**

v0 paste has exactly **one insertion primitive**: `NSPasteboard` write + simulated `Cmd+V`. There is **no text-selection or deletion primitive** in v0.

To replace already-inserted raw text with cleaned text, the session would need to:
- **Blind-delete** the raw text the inserter *believes* it streamed (N backspaces or Shift+Arrow×N)
- Paste the cleaned text

But the actual text in the target app **diverges from the inserter's count** under:
- Autocorrect / spell-check (adds/removes chars in the background)
- User cursor movement (they've edited or moved mid-paste)
- Line wrapping / IME (multibyte characters, emoji)
- Rich text fields with hidden markup

**Result:** The blind-delete undershoots or overshoots. Cleaned text lands in the wrong place, or the user's document is partially nuked.

**The AX solution** (`PasteMode.accessibility` from architecture §11) is a **v1 placeholder**. It can query focused element properties and select text reliably. But it is **not in v0**, and adding it now bloats the first release.

### 2. **Streaming multiplies the project's #1 unverified risk**

Architecture §11 flags `[unverified]` (macOS 26.4 paste-provenance bypass):
> "Write+Cmd+V avoids macOS 26.4 Terminal paste-provenance prompt. Empirically test at P6."

- **Today (v0):** One dictation = one `Cmd+V` = potentially one paste prompt (if the bypass fails).
- **With streaming:** N finalized segments = N `Cmd+V` events = N potential prompts, **concentrated in Terminal** (the exact app the ship gate tests).

If the bypass fails in Terminal, streaming turns a single-prompt risk into a multi-prompt UX disaster, right where the moat is tested.

### 3. **The live-feedback need is already met**

The v0 architecture **already delivers the "live streaming" UX** the requirement seeks:

```
CaptureSession.partials()  ──►  TranscriptOverlayPanel (live HUD)
```

The overlay shows partial transcript chunks updating in real-time (<200ms latency, architecture §12 budget). The user **sees the words accumulate as they speak** — the core streaming feedback.

Streaming into the **target app** (the document they're dictating into) adds:
- Risk of multiple pastes (§2)
- Risk of broken replace (§1)
- Minimal UX gain over the overlay they already see

### 4. **The scope mismatch in the question**

Question 1 asks: *"Should `PasteboardWriter` have two new methods?"*

This frames it as a small API addition. The **actual scope** is:

- A new insertion primitive (per-finalized-segment paste + tracked-char-count replace)
- A behavior-contract change (paste no longer means "final delivery" — it means "temporary accumulation")
- Cancellation semantics change (can no longer guarantee "nothing left the session")
- Settings read at session start (not per-chunk — see Q5)

This is **not** a two-method change. It's a **foundational contract shift** that touches `CaptureSession`, `PasteboardWriter`, `TextInserting` protocol, and error handling.

---

## Questions Addressed (given safe assumptions)

**Assuming the human decides streaming is essential and accepts the risks,** here are the architectural answers:

### Q1: Paste Strategy — Where to add the streaming API

**NOT `PasteboardWriter` methods.** Use the **existing `StreamingTextInserting` protocol** (already defined in `/SpeakCore/Paste/StreamingTextInserting.swift`):

```swift
public protocol StreamingTextInserting: Sendable {
    /// Deliver one chunk of raw text.
    func insertChunk(_ text: String) async throws
    /// Finalize the stream.
    func finalize() async throws
}
```

**Rationale:**
- `TextInserting` = full-text delivery (the current v0 semantics)
- `StreamingTextInserting` = chunk-by-chunk delivery (the new streaming path)
- By protocol, not methods, you keep `PasteboardWriter` conforming to one contract at a time
- Tests and call-sites explicitly choose streaming vs. final

**Implementation path:**
1. Rename `StreamingTextInserting` to `StreamingRawTextInserting` (name clarifies the contract: raw text streaming, not cleanup streaming)
2. Create `StreamingRawTextPasteboardWriter: StreamingRawTextInserting`
3. Implement `insertChunk(_:)` as:
   - Write the chunk to a **temporary pasteboard**
   - Post Cmd+V (the chunk lands in the cursor position)
   - **Track cumulative char count** (for the later blind-delete attempt)
4. Implement `finalize()` as:
   - On cleanup success: `runBlindReplace(oldChars: trackedCount, newText: cleanedText)`
   - On cleanup failure: no-op (raw text stays, user has fallback)

### Q2: When to stream raw text — Best cadence

**Option B: Only finalized chunks** (REQUIRED, not optional).

```swift
// In CaptureSession.ingest(_:)
if chunk.isFinal {
    // Safe to stream this chunk — it won't be revised.
    try await streamingInserter?.insertChunk(chunk.text)
}
```

**Why NOT Option A (every ingest call):**

SpeechAnalyzer with `.progressiveTranscription` (see `AppleSpeechTranscriber`) emits **volatile chunks that get revised** (you saw this in `CaptureSession.ingest()`):
- Volatile (isFinal==false): "hello w" → "hello wo" → "hello wor" → "hello world"
- Final (isFinal==true): "hello world" (stable, won't change)

Pasting volatile text means **pasting text that later changes**. Once it lands in the document, you cannot un-write it.

**Option C (accumulate and paste every N words / time threshold)** is also unsafe for the same reason.

### Q3: Moat Safety — Pasteboard Read Check

The moat audit (`make verify-moat`) checks that the codebase **calls no pasteboard read APIs**:

```
Denylist: NSPasteboard.general.string, dataForType, .availableTypeFromArray(...), etc.
```

`StreamingRawTextPasteboardWriter` will pass this audit because `insertChunk()` only:
- Writes to pasteboard: `NSPasteboard.general.setString(...)`
- Simulates Cmd+V: posts `CGEvent`

**But this is necessary, not sufficient.** The real exposure is:

- **macOS 26.4 paste-provenance prompt** (Terminal): one per `Cmd+V`. With N chunks, N prompts **in the app the ship gate tests**.
- **Live Terminal test required** (P6 human gate): Dictate a 5-segment utterance with streaming enabled. Verify:
  - Each segment lands in Terminal without a prompt (if the bypass holds)
  - OR document how many prompts fire (risk acceptance)

**Action:** Add a new test case to `quality.md` §3 (compatibility matrix):
```
| Terminal | Paste works (raw streaming) | Hotkey fires | N/1 paste-prompts | streaming=<risk> |
```

### Q4: Edge Cases — Semantics Change

These are **not edge cases — they are contract changes:**

#### **Cancel during streaming**

- **Before:** `cancel()` → stream aborts, no paste landed, user's document unchanged.
- **After:** `cancel()` → raw text already landed, `finalize()` not called, cleanup never runs, raw text **stays** in the document.

**This is a behavior flip.** Document it in Settings and onboarding.

#### **User disables streaming mid-dictation**

This **must not happen** (Q5 addresses it by latching the toggle at session start). But if it does:
- Latched decision at session start means the toggle's current value is ignored mid-session
- Disable applies to the *next* session
- The current session continues streaming if it was started with streaming enabled

#### **Cleanup fails / times out**

- **Current contract:** cleanup timeout → fallback to raw, paste raw, move on (no error).
- **With streaming:** Cleanup failure → raw already landed, clean paste was going to replace it, cleanup failed, so raw stays. **Same outcome** (raw is pasted), but causality is different. Update error messaging: "Cleanup failed; using raw transcript you already see."

### Q5: Settings Integration — Decision Latching

**The setting is READ ONCE at session start, not per-chunk.**

```swift
// In SpeakEngine.newSession()
let streamingRawEnabled = settings.streamingRawTextEnabled  // read once
let session = CaptureSession(
    transcriber: ...,
    cleaner: ...,
    streamingInserter: streamingRawEnabled ? StreamingRawTextPasteboardWriter() : nil
)
```

**Why not per-chunk reads:**

1. **Avoid mid-session toggle confusion:** User disables streaming during dictation. Which behavior? Revert to buffered, or keep streaming? A state machine nightmare.
2. **Matches the precedent:** Multi-language support (H1) reads `language` at `newSession()` time, not per-chunk.
3. **Settings toggle applies next session:** User changes "Streaming Raw" toggle. Current session (already started) keeps its choice. Next session picks up the new setting.

**SettingsStore addition:**

```swift
// In Keys
static let streamingRawTextEnabled = "speak.settings.streamingRawTextEnabled"

// In SettingsStore
@Observable
public var streamingRawTextEnabled: Bool {
    get {
        access(keyPath: \.streamingRawTextEnabled)
        return defaults.bool(forKey: Keys.streamingRawTextEnabled)
    }
    set {
        withMutation(keyPath: \.streamingRawTextEnabled) {
            defaults.set(newValue, forKey: Keys.streamingRawTextEnabled)
        }
    }
}

// In init
defaults.register(defaults: [
    Keys.streamingRawTextEnabled: false  // disabled by default in v0
])
```

---

## Complete API Shapes (if proceeding)

### StreamingRawTextPasteboardWriter

```swift
// Location: SpeakCore/Paste/StreamingRawTextPasteboardWriter.swift

public final class StreamingRawTextPasteboardWriter: StreamingRawTextInserting, Sendable {
    private let log = SpeakLog.paste
    
    // Injected seams (same pattern as PasteboardWriter)
    let isAccessibilityTrusted: @Sendable () -> Bool
    let isFocusedFieldSecure: @Sendable () -> Bool
    let settle: Duration
    let pasteEventGap: Duration
    let writeClipboard: @Sendable (String) -> Void
    let postEvent: @Sendable (CGEvent) -> Void
    
    // Tracking state for the replace operation
    private var accumulatedChars: Int = 0
    
    public init(
        isAccessibilityTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        isFocusedFieldSecure: @escaping @Sendable () -> Bool = { focusedElementIsSecureField() },
        settle: Duration = .milliseconds(100),
        pasteEventGap: Duration = .milliseconds(10),
        writeClipboard: @escaping @Sendable (String) -> Void = PasteboardWriter.defaultWriteClipboard,
        postEvent: @escaping @Sendable (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.isFocusedFieldSecure = isFocusedFieldSecure
        self.settle = settle
        self.pasteEventGap = pasteEventGap
        self.writeClipboard = writeClipboard
        self.postEvent = postEvent
    }
    
    /// Stream one finalized chunk of raw text to the cursor.
    public func insertChunk(_ text: String) async throws {
        guard !text.isEmpty else { return }  // silently ignore empty chunks
        
        log.info("StreamingRawTextPasteboardWriter: streaming \(text.count) chars")
        
        // 1. Clipboard floor: write the chunk
        writeClipboard(text)
        
        // 2. AX trust gate
        guard isAccessibilityTrusted() else {
            throw SpeakError.pasteRequiresAccessibility(text: text)
        }
        
        // 3. Secure field gate
        if isFocusedFieldSecure() {
            throw SpeakError.pasteIntoSecureField(text: text)
        }
        
        // 4. Settle + paste
        try await Task.sleep(for: settle)
        try await simulateCmdV()
        
        // 5. Track char count for later replace
        accumulatedChars += text.count
    }
    
    /// Finalize the stream. Call after all chunks are delivered.
    public func finalize() async throws {
        log.info("StreamingRawTextPasteboardWriter: stream finalized, \(accumulatedChars) total chars pasted")
        // No-op at this stage. The replace happens at cleanup time in CaptureSession.
    }
    
    // ... (simulateCmdV copied from PasteboardWriter)
}
```

### CaptureSession extension (streaming integration)

```swift
// Location: SpeakCore/Engine/CaptureSession+StreamingRaw.swift

extension CaptureSession {
    /// Run the streaming raw-text insert, then later the cleanup+final-paste sequence.
    /// Called during stop() if streamingInserter is not nil.
    private func runStreamingRaw(rawText: String) async throws {
        guard let inserter = streamingInserter else { return }
        
        // Tokenize the raw text into finalized-chunk boundaries.
        // (This is a simplified version; real impl would match SpeechAnalyzer's
        //  actual finalized segments from the streaming phase.)
        let chunks = rawText.split(separator: " ", omittingEmptySubsequences: true)
                            .map(String.init)
        
        for chunk in chunks {
            try await inserter.insertChunk(chunk + " ")  // preserve spaces
        }
        try await inserter.finalize()
    }
    
    /// After cleanup, replace the streamed raw with cleaned text via blind delete.
    private func runStreamingReplace(oldChars: Int, newText: String) async throws {
        // [unverified] This is a fragile blind-delete operation.
        // Real safety requires AX-based selection + replacement (v1).
        
        guard let inserter = streamingInserter as? StreamingRawTextPasteboardWriter else {
            return
        }
        
        // Simulate: Shift+End × oldChars to select what we pasted, then paste the new text.
        // [DANGER] This can fail under autocorrect, cursor movement, multibyte, etc.
        // Only proceed if the user has acknowledged the risk in Settings.
        
        let log = SpeakLog.engine
        log.warning("StreamingRawTextPasteboardWriter: attempting blind replace of \(oldChars) chars with \(newText.count) chars")
        
        // Build the delete plan: Shift+End once (select to EOL), repeat as needed.
        // [decision: per-char backspace is safer than Shift+Arrow for large counts,
        //  but slower. Use Shift+End for speed; trade reliability.]
        
        // Post the Shift+End events...
        // Post the cleanup+paste Cmd+V...
        // Log the outcome (success, but note: unverified under concurrent edits).
    }
}
```

---

## Implementation Sequence (if proceeding)

1. **Add setting to SettingsStore** (`streamingRawTextEnabled: Bool`, default false)
2. **Implement `StreamingRawTextPasteboardWriter`** (copy PasteboardWriter, add chunk tracking)
3. **Wire into `CaptureSession`:** Accept `streamingInserter` parameter, call `insertChunk` per finalized segment
4. **Implement `runStreamingReplace`** (the fragile blind-delete — mark [unverified])
5. **Unit tests:**
   - `StreamingRawTextPasteboardWriterTests`: chunk delivery, tracking, settle/gap delays
   - Mock `postEvent` and `writeClipboard` (don't touch real clipboard)
   - Verify Cmd+V is posted N times (once per chunk)
6. **Integration test:**
   - Dictate a multi-segment utterance with streaming enabled
   - Verify raw chunks land in TextEdit (testable)
   - Verify cleaned text replaces after cleanup (test both success and cleanup-timeout paths)
7. **Live Terminal test** (P6 human gate): Verify streaming doesn't trigger the paste-provenance prompt N times

---

## Safety Notes — Moat & Constraints

### Pasteboard Read
✅ `insertChunk` calls no read API — passes `make verify-moat` (necessary condition)
⚠️ Requires live Terminal test (sufficient condition pending — see Q3)

### Hard Constraint: No third-party deps
✅ No new dependencies — uses only NSPasteboard, CGEvent, DispatchTime

### Hard Constraint: Never block main thread
✅ `insertChunk` is `async` with `Task.sleep` (non-blocking)

### Concurrency
⚠️ `accumulatedChars` tracking requires actor isolation (must be stored on CaptureSession, not StreamingRawTextPasteboardWriter)

### Accessibility Permission
✅ Both `AXIsProcessTrusted()` and secure-field detection (like PasteboardWriter) required

---

## Recommendation

**Default v0 design** — ship with `streamingRawTextEnabled: false`:
- Live overlay shows partials (already working, BEAT feature)
- One final paste at stop (safe, well-tested)
- Pairs with cleanup toggle for full control
- Shipping date unaffected

**If streaming is essential:**
1. Human approval required (this spec surfaces the contract changes in Q4)
2. Default to disabled in v0, feature-flag enabled
3. "Streaming raw text" documented as **experimental** with **unverified replace safety**
4. P6 live Terminal test is a hard prerequisite
5. Separate v0.1 task: "Replace via AX API" (eliminates the blind-delete hazard)

**Timeframe:** The implementation is **not blocking v0** (can land as a v0.1 feature toggle with the above safeguards).

---

## Verification

- [x] Streaming protocol (`StreamingRawTextInserting`) already exists  
- [x] Finalized-chunk pattern verified in `CaptureSession.ingest()`  
- [x] Settings latching pattern precedent in H1 (language)  
- [x] Paste moat primitives verified (`NSPasteboard`, `CGEvent`)  
- [ ] macOS 26.4 paste-provenance bypass test (Terminal, live, P6 gate)  
- [ ] Blind-replace under autocorrect / multibyte (marked `[unverified]`, requires live test)  
- [ ] AX-based selection + replace (v1 enhancement, out of v0 scope)

---

**This spec is complete and locked, pending the human's decision on whether to pursue streaming in v0 or defer to v0.1 with the "Replace via AX" prerequisite.**
