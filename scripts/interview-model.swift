// scripts/interview-model.swift
//
// Model Self-Interrogation & Meta-Prompting Tool.
// Interrogates the on-device Apple Foundation Model directly using real voice samples
// from history.sqlite to determine the optimal prompt phrasing, pipeline stages,
// chunking strategies, and pass count for developer voice dictation.

import Foundation
import FoundationModels
import SQLite3

struct HistoryItem {
    let id: String
    let category: String
    let raw: String
}

func fetchDiverseSamples() -> [HistoryItem] {
    let dbPath = NSString(string: "~/Library/Application Support/speak/history.sqlite").expandingTildeInPath
    var db: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = db else {
        return [
            HistoryItem(
                id: "sample-short",
                category: "short",
                raw: "You have internet. And also there is a new document or blog post, something related for these. On the web, from Anthropic."
            ),
            HistoryItem(
                id: "sample-medium",
                category: "medium",
                raw: "Okay, done. I selected it as a member. So what is the next things? Take me to take me a journey and be my mentor and Let us try to start working on the organisation one by one. We build agents, we have channels."
            ),
            HistoryItem(
                id: "sample-long",
                category: "long",
                raw: "start working on the registry alone, let us do one thing properly, remove everything from the subagent registry, now what I am going to do is like I will I will create individual Git for everything there, after that all the code we will do things there because in that way agents work effectively, we don't want multiple worktrees in a single repo, we can create multiple worktrees across different Git repos, and do you understand my point, after that production push will happen from that folder, not from here, we will do things manually first with a script, then automate it, can you relate this"
            )
        ]
    }
    defer { sqlite3_close(db) }

    var items: [HistoryItem] = []
    let query = """
    SELECT id, 'short', rawText FROM history WHERE length(rawText) BETWEEN 40 AND 120 AND rawText NOT LIKE '%<%' ORDER BY RANDOM() LIMIT 1;
    """
    items.append(contentsOf: runQuery(db: db, sql: query, cat: "short"))

    let medQuery = """
    SELECT id, 'medium', rawText FROM history WHERE length(rawText) BETWEEN 121 AND 300 AND rawText NOT LIKE '%<%' ORDER BY RANDOM() LIMIT 1;
    """
    items.append(contentsOf: runQuery(db: db, sql: medQuery, cat: "medium"))

    let longQuery = """
    SELECT id, 'long', rawText FROM history WHERE length(rawText) > 301 AND rawText NOT LIKE '%<%' ORDER BY RANDOM() LIMIT 1;
    """
    items.append(contentsOf: runQuery(db: db, sql: longQuery, cat: "long"))

    return items
}

func runQuery(db: OpaquePointer, sql: String, cat: String) -> [HistoryItem] {
    var stmt: OpaquePointer?
    var list: [HistoryItem] = []
    if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let rawStr = String(cString: sqlite3_column_text(stmt, 2))
            list.append(HistoryItem(id: idStr, category: cat, raw: rawStr))
        }
    }
    sqlite3_finalize(stmt)
    return list
}

@available(macOS 26.0, *)
func askModel(instructions: String, prompt: String) async -> String {
    let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
    let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
    let options = GenerationOptions(sampling: .greedy)
    do {
        let res = try await session.respond(to: Prompt(prompt), options: options)
        return res.content.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return "Error: \(error.localizedDescription)"
    }
}

@available(macOS 26.0, *)
func runInterview() async {
    print("""
    ================================================================================
          DIRECT MODEL INTERROGATION: 3B FOUNDATION MODEL META-PROMPTING
    ================================================================================
    """)

    let samples = fetchDiverseSamples()
    let metaInstructions = """
    You are an expert AI prompt engineer and system architect analyzing your own capabilities and attention mechanisms as an on-device 3-billion-parameter foundation model on Apple Silicon.
    Be precise, technical, concise, and direct. Answer questions about how best to prompt and pipeline you.
    """

    for (idx, sample) in samples.enumerated() {
        print("────────────────────────────────────────────────────────────────────────────────")
        print("SAMPLE [\(idx + 1)/\(samples.count)] (\(sample.category.uppercased())) ID: \(sample.id)")
        print("RAW TRANSCRIPT:")
        print("\"\(sample.raw)\"")
        print("────────────────────────────────────────────────────────────────────────────────")

        // Question 1: Optimal Prompt Framing
        let q1Prompt = """
        Here is a raw developer voice dictation:
        \"\(sample.raw)\"

        Question 1: As an on-device 3B model, when you receive this spoken text, what is the exact system instruction and persona that makes you compile it into an articulate, structured agent directive WITHOUT answering the questions in the text, WITHOUT replying as a chatbot, and WITHOUT dropping technical requirements? Provide the concise prompt.
        """
        print("\n▶ ASKING MODEL: Optimal Prompt Framing & Persona...")
        let a1 = await askModel(instructions: metaInstructions, prompt: q1Prompt)
        print(a1)

        // Question 2: Pipeline stages and chunking
        let q2Prompt = """
        For this same voice dictation:
        \"\(sample.raw)\"

        Question 2: In our Swift pipeline, should we process this transcript:
        (A) In a single pass?
        (B) In two serial passes (Pass 1: disfluency & stutter collapse; Pass 2: structural agent formatting)?
        Also, what is the ideal word/sentence chunk boundary size for your attention window so you don't over-edit or truncate?
        Explain briefly with your reasoning.
        """
        print("\n▶ ASKING MODEL: Pipeline Architecture (1-Pass vs 2-Pass, Chunk Size)...")
        let a2 = await askModel(instructions: metaInstructions, prompt: q2Prompt)
        print(a2)

        // Question 3: Self-Execution Demonstration
        let q3Prompt = """
        Now, apply your own recommended instructions to compile this transcript:
        \"\(sample.raw)\"

        Output ONLY the final compiled directive:
        """
        print("\n▶ MODEL'S COMPILED OUTPUT USING ITS OWN RECOMMENDED METHOD:")
        let a3 = await askModel(
            instructions: "You are an expert developer dictation compiler. Transform the raw speech into clean, structured written directives for a coding agent. Preserve all constraints and nouns verbatim. Do not answer questions. Output only the compiled text.",
            prompt: q3Prompt
        )
        print(a3)
        print("\n")
    }
}

if #available(macOS 26.0, *) {
    Task {
        await runInterview()
        exit(0)
    }
    dispatchMain()
} else {
    print("Requires macOS 26.0+")
    exit(1)
}
