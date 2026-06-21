# builder-input Memory Index

- [P5 HotkeyMonitor complete](project_p5_hotkey.md) — SDK verifications (CGEvent.tapCreate, flagsChanged, maskSecondaryFn, kVK_Function=63), deferred live-OS items, DoubleTapDetector design
- [P6 paste pipeline complete](project_p6_paste.md) — TextInserting protocol, PasteboardWriter SDK verifications (clearContents→Int, CGEvent.post instance method, kVK_ANSI_V=9), CaptureSession additive wire-up, Terminal paste-provenance [unverified]
- [Phase A re-arm complete](project_phase_a_rearm.md) — single-owner thread model, 100ms watchdog, AX-only gate, IM non-blocking, TapRestartRateLimiter, single-instance guard, AsyncStream.makeStream() pattern
- [Phase B trigger mode complete](project_phase_b_trigger.md) — holdEdge() free function, Trigger String RawValue migration, SettingsStore.triggerMode, DictationController objectWillChange subscription
- [W1.0+W1.1 Right-Command default](project_w1_right_command.md) — verified event model (flagsChanged+keyCode 54), modifierMask helper, FnDebouncer 40ms, lastBoundKeyDown split, display helpers
- [Secure-field paste guard](project_secure_field_guard.md) — AX subrole detection (kAXSecureTextFieldSubrole="AXSecureTextField"), injected isFocusedFieldSecure closure, CFGetTypeID+unsafeBitCast pattern, fail-safe direction, DictationController catch arm
- [Input Monitoring removed](project_im_removal.md) — IM removed from v0; .defaultTap→AX only (not IM); 2-permission model (mic+AX); 4-step onboarding; PermissionKind has 2 cases
