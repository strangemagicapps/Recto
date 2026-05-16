import Testing
@testable import Recto

@Suite("ScriptParser")
struct ScriptParserTests {
    @Test func plainProseTokenisation() {
        let parsed = ScriptParser.parse("the quick brown fox")

        #expect(parsed.normalisedWords == ["the", "quick", "brown", "fox"])
        #expect(parsed.displayWords.map(\.text) == ["the", "quick", "brown", "fox"])
        #expect(parsed.displayWords.map(\.id) == [0, 1, 2, 3])
        #expect(parsed.displayWords.map(\.trailingSpace) == [true, true, true, false])
        #expect(parsed.displayWords.allSatisfy { !$0.trailingNewline })
    }

    @Test func punctuationNormalisation() {
        let parsed = ScriptParser.parse("Hello, world! \"Yes\" -- (maybe).")

        #expect(
            parsed.normalisedWords == ["hello", "world", "yes", "", "maybe"]
        )
        #expect(
            parsed.displayWords.map(\.text)
                == ["Hello,", "world!", "\"Yes\"", "--", "(maybe)."]
        )
    }

    @Test func apostrophePreservation() {
        let straight = ScriptParser.parse("don't stop rock'n'roll")
        #expect(straight.normalisedWords == ["don't", "stop", "rock'n'roll"])

        let curly = ScriptParser.parse("don\u{2019}t stop")
        #expect(curly.normalisedWords == ["don\u{2019}t", "stop"])

        // Leading/trailing apostrophes count as edge punctuation and are
        // stripped; only internal apostrophes survive.
        let quoted = ScriptParser.parse("'twas 'brillig'")
        #expect(quoted.normalisedWords == ["twas", "brillig"])
    }

    @Test func mixedCaseNormalisation() {
        let parsed = ScriptParser.parse("MacBeth ShallNot SLEEP Café")
        #expect(parsed.normalisedWords == ["macbeth", "shallnot", "sleep", "café"])
        #expect(parsed.displayWords.map(\.text) == ["MacBeth", "ShallNot", "SLEEP", "Café"])
    }

    @Test func lineBreaksPreservedAsTrailingNewline() {
        let parsed = ScriptParser.parse("first line\nsecond line\nthird")

        #expect(parsed.normalisedWords == ["first", "line", "second", "line", "third"])

        let words = parsed.displayWords
        #expect(words[0].trailingSpace && !words[0].trailingNewline)
        #expect(!words[1].trailingSpace && words[1].trailingNewline)
        #expect(words[2].trailingSpace && !words[2].trailingNewline)
        #expect(!words[3].trailingSpace && words[3].trailingNewline)
        #expect(!words[4].trailingSpace && !words[4].trailingNewline)
    }

    @Test func emptyInput() {
        let empty = ScriptParser.parse("")
        #expect(empty.title == "")
        #expect(empty.displayWords.isEmpty)
        #expect(empty.normalisedWords.isEmpty)

        let whitespaceOnly = ScriptParser.parse("   \n\t  \n")
        #expect(whitespaceOnly.displayWords.isEmpty)
        #expect(whitespaceOnly.normalisedWords.isEmpty)
    }

    @Test func singleWordInput() {
        let parsed = ScriptParser.parse("Hello.", title: "Greeting")

        #expect(parsed.title == "Greeting")
        #expect(parsed.normalisedWords == ["hello"])
        #expect(parsed.displayWords.count == 1)

        let only = parsed.displayWords[0]
        #expect(only.id == 0)
        #expect(only.text == "Hello.")
        #expect(!only.trailingSpace)
        #expect(!only.trailingNewline)
    }

    @Test func longInputPerformanceSmoke() {
        let tokens = (0..<1500).map { "Word\($0)," }
        let raw = tokens.joined(separator: " ")

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let parsed = ScriptParser.parse(raw)
            #expect(parsed.normalisedWords.count == 1500)
            #expect(parsed.normalisedWords.first == "word0")
            #expect(parsed.normalisedWords.last == "word1499")
        }

        // Generous bound — this is a smoke test, not a benchmark.
        #expect(elapsed < .seconds(1))
    }
}
