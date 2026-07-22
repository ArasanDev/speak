//
//  TextDiffResolver.swift
//  SpeakCore
//

import Foundation

public enum TokenState: Sendable, Equatable {
    case normal
    case canceled
    case inserted
}

public struct DiffToken: Sendable, Equatable {
    public let text: String
    public let state: TokenState
    
    public init(text: String, state: TokenState) {
        self.text = text
        self.state = state
    }
}

public struct TextDiffResolver: Sendable {
    public init() {}
    
    public func resolve(raw: String, cleaned: String) -> [DiffToken] {
        let rawWords = raw.split(separator: " ").map { String($0) }
        let cleanedWords = cleaned.split(separator: " ").map { String($0) }
        
        var lcsLength = Array(repeating: Array(repeating: 0, count: cleanedWords.count + 1), count: rawWords.count + 1)
        
        for i in 1...rawWords.count {
            for j in 1...cleanedWords.count {
                if rawWords[i-1] == cleanedWords[j-1] {
                    lcsLength[i][j] = lcsLength[i-1][j-1] + 1
                } else {
                    lcsLength[i][j] = max(lcsLength[i-1][j], lcsLength[i][j-1])
                }
            }
        }
        
        var i = rawWords.count
        var j = cleanedWords.count
        var result: [DiffToken] = []
        
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && rawWords[i-1] == cleanedWords[j-1] {
                result.append(DiffToken(text: rawWords[i-1], state: .normal))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || lcsLength[i][j-1] >= lcsLength[i-1][j]) {
                result.append(DiffToken(text: cleanedWords[j-1], state: .inserted))
                j -= 1
            } else if i > 0 && (j == 0 || lcsLength[i][j-1] < lcsLength[i-1][j]) {
                result.append(DiffToken(text: rawWords[i-1], state: .canceled))
                i -= 1
            }
        }
        
        return result.reversed()
    }
}
