// App/Pet/PetAttentionProviding.swift
//
// FE-1 (specs/frontend-identity.md §5): the seam for the AVB-7 inbox count.
// "`attention` is driven by the AVB-7 inbox count (`pendingAndPresented`) —
// Pip IS the inbox badge. Until AVB-7 lands, the state exists with a stub
// provider returning 0." One protocol, no store dependency — AVB-7 implements
// a real conformer later without touching Pip's code.

import Foundation

/// Supplies the count Pip's `.attention` state and badge are driven by.
/// `count > 0` maps to `PetStateInputs.hasAttention == true` (see `PetState.swift`).
public protocol PetAttentionProviding: Sendable {
    /// Number of pending-and-presented items awaiting the human's attention.
    var count: Int { get async }
}

/// Stub conformer — always reports zero. This is the ONLY conformer until
/// AVB-7 lands; Pip never regresses because `.attention` simply never fires.
/// [decision FE-1: stub, not a TODO-throw — the seam must compile and run
///  cleanly with zero attention items, which is also the correct v0 behavior.]
public struct StubPetAttentionProvider: PetAttentionProviding {
    public init() {}
    public var count: Int {
        get async { 0 }
    }
}
