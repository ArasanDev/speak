// App/DictationController+CLI.swift
//
// CLI IPC entry points (W2.3). Bridges `speak --start` / `--stop` into the
// same begin/end path the hotkey uses. The idempotency gate lives in
// `CLIPortServer` (checks `icon` before calling); dispatch here is intentionally
// simple and trusts that gate.

import Foundation

extension DictationController {

    // MARK: - CLICommandHandler (W2.3)

    /// Called by `CLIPortServer` when a `--start` command arrives.
    /// Dispatches `beginDictation()` on the main actor (already on main — the
    /// port callback schedules on CFRunLoopGetMain). Reuses the hotkey path exactly.
    func cliBeginDictation() {
        Task { [weak self] in
            await self?.beginDictation()
        }
    }

    /// Called by `CLIPortServer` when a `--stop` command arrives.
    /// Dispatches `endDictation()` on the main actor. Reuses the hotkey path exactly.
    func cliEndDictation() {
        Task { [weak self] in
            await self?.endDictation()
        }
    }
}
