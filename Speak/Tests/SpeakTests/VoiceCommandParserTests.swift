// SpeakTests/VoiceCommandParserTests.swift
//
// PE-3.1 unit coverage for VoiceCommandParser.
// All tests are deterministic — no I/O, no live model pass required.

@testable import SpeakCore
import Testing

@Suite("VoiceCommandParser")
struct VoiceCommandParserTests {

    // Stable IDs from DefaultProfiles — pulled at test time so tests stay in sync
    // with the actual built-ins without duplicating the UUID literals.
    private let agentID = DefaultProfiles.agent.id
    private let writeID = DefaultProfiles.write.id
    private let noteID  = DefaultProfiles.note.id

    private func detect(_ s: String) -> VoiceCommand? {
        VoiceCommandParser.detect(s, agentProfileID: agentID, writeProfileID: writeID, noteProfileID: noteID)
    }

    // MARK: - Spec cases

    @Test func fixColonSetsCategory() {
        let cmd = detect("fix: paste not working")
        #expect(cmd?.category == .fix)
        #expect(cmd?.destination == nil)
        #expect(cmd?.strippedTranscript == "paste not working")
    }

    @Test func asACommitColonSetsCategory() {
        let cmd = detect("as a commit: added login")
        #expect(cmd?.category == .commit)
        #expect(cmd?.destination == nil)
        #expect(cmd?.strippedTranscript == "added login")
    }

    @Test func noteColonSetsDestination() {
        let cmd = detect("note: call mom tomorrow")
        #expect(cmd?.destination == noteID)
        #expect(cmd?.category == nil)
        #expect(cmd?.strippedTranscript == "call mom tomorrow")
    }

    @Test func midSentenceFixIsIgnored() {
        let cmd = detect("hey can you fix the login")
        #expect(cmd == nil)
    }

    @Test func commitUppercaseIsCaseInsensitive() {
        let cmd = detect("COMMIT: update deps")
        #expect(cmd?.category == .commit)
        #expect(cmd?.strippedTranscript == "update deps")
    }

    @Test func switchToWriteSetsDestination() {
        let cmd = detect("switch to write: let them know it's done")
        #expect(cmd?.destination == writeID)
        #expect(cmd?.category == nil)
        #expect(cmd?.strippedTranscript == "let them know it's done")
    }

    @Test func plainTranscriptReturnsNil() {
        let cmd = detect("refactor the parser")
        #expect(cmd == nil)
    }

    // MARK: - Additional coverage

    @Test func agentColonSetsDestination() {
        let cmd = detect("agent: open the pr description")
        #expect(cmd?.destination == agentID)
        #expect(cmd?.category == nil)
        #expect(cmd?.strippedTranscript == "open the pr description")
    }

    @Test func shellColonSetsCategory() {
        let cmd = detect("shell: list all hidden files")
        #expect(cmd?.category == .shell)
        #expect(cmd?.strippedTranscript == "list all hidden files")
    }

    @Test func runColonSetsShellCategory() {
        let cmd = detect("run: git status")
        #expect(cmd?.category == .shell)
        #expect(cmd?.strippedTranscript == "git status")
    }

    @Test func codeColonSetsCategory() {
        let cmd = detect("code: let x equals five")
        #expect(cmd?.category == .code)
        #expect(cmd?.strippedTranscript == "let x equals five")
    }

    @Test func askColonSetsCategory() {
        let cmd = detect("ask: why does this fail")
        #expect(cmd?.category == .ask)
        #expect(cmd?.strippedTranscript == "why does this fail")
    }

    @Test func writeColonSetsDestination() {
        let cmd = detect("write: send her the report")
        #expect(cmd?.destination == writeID)
        #expect(cmd?.strippedTranscript == "send her the report")
    }

    @Test func asCodeWithoutColonStripsPrefix() {
        let cmd = detect("as code let x equals five")
        #expect(cmd?.category == .code)
        #expect(cmd?.strippedTranscript == "let x equals five")
    }

    @Test func asACommitWithoutColonStripsPrefix() {
        let cmd = detect("as a commit added the login button")
        #expect(cmd?.category == .commit)
        #expect(cmd?.strippedTranscript == "added the login button")
    }

    @Test func switchToAgentWithColonSetsDestination() {
        let cmd = detect("switch to agent: implement the auth flow")
        #expect(cmd?.destination == agentID)
        #expect(cmd?.strippedTranscript == "implement the auth flow")
    }

    @Test func emptyInputReturnsNil() {
        #expect(detect("") == nil)
        #expect(detect("   ") == nil)
    }

    @Test func triggerOnlyWithNoBody() {
        let cmd = detect("fix:")
        // Trigger matched, stripped transcript is empty.
        #expect(cmd?.category == .fix)
        #expect(cmd?.strippedTranscript == "")
    }

    @Test func longNaturalPhraseNoMatchIsNil() {
        #expect(detect("could you please fix the login issue") == nil)
        #expect(detect("let me ask about the architecture") == nil)
    }

    @Test func fixThisNaturalForm() {
        let cmd = detect("fix this button is not responding")
        #expect(cmd?.category == .fix)
        #expect(cmd?.strippedTranscript == "button is not responding")
    }

    @Test func mixedCaseSwitchToWrite() {
        let cmd = detect("SWITCH TO WRITE: send the update")
        #expect(cmd?.destination == writeID)
        #expect(cmd?.strippedTranscript == "send the update")
    }
}
