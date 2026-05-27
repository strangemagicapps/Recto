import Testing
@testable import Recto

@Suite("ScriptParser")
struct ScriptParserTests {

    // MARK: - Plain prose tokenisation

    @Test func `plain prose splits on spaces into normalised words`() {
        let parsed = ScriptParser.parse("the quick brown fox")
        #expect(parsed.normalisedWords == ["the", "quick", "brown", "fox"])
    }

    @Test func `plain prose preserves the original token text`() {
        let parsed = ScriptParser.parse("the quick brown fox")
        #expect(parsed.displayWords.map(\.text) == ["the", "quick", "brown", "fox"])
    }

    @Test func `display word ids run in display order`() {
        let parsed = ScriptParser.parse("the quick brown fox")
        #expect(parsed.displayWords.map(\.id) == [0, 1, 2, 3])
    }

    @Test func `every plain-text token carries a match index`() {
        let parsed = ScriptParser.parse("the quick brown fox")
        #expect(parsed.displayWords.map(\.matchIndex) == [0, 1, 2, 3])
    }

    @Test func `plain prose produces a 1-to-1 display and normalised mapping`() {
        let parsed = ScriptParser.parse("the quick brown fox")
        #expect(parsed.displayWords.count == parsed.normalisedWords.count)
        for word in parsed.displayWords {
            #expect(word.matchIndex == word.id)
        }
    }

    @Test func `displayIndex maps a match index back to its display position`() {
        let parsed = ScriptParser.parse("the quick brown fox")
        #expect(parsed.displayIndex(forMatchIndex: 2) == 2)
    }

    @Test func `displayIndex returns nil for an out-of-range match index`() {
        let parsed = ScriptParser.parse("the quick brown fox")
        #expect(parsed.displayIndex(forMatchIndex: 4) == nil)
    }

    @Test func `interior words carry a trailing space`() {
        let parsed = ScriptParser.parse("the quick brown fox")
        let leading = parsed.displayWords.dropLast().map(\.trailingSpace)
        #expect(leading == [true, true, true])
    }

    @Test func `the final word has no trailing space`() {
        let parsed = ScriptParser.parse("the quick brown fox")
        #expect(parsed.displayWords.last?.trailingSpace == false)
    }

    // MARK: - Punctuation normalisation

    @Test func `trailing punctuation is stripped from normalised words`() {
        let parsed = ScriptParser.parse("Hello, world!")
        #expect(parsed.normalisedWords == ["hello", "world"])
    }

    @Test func `surrounding punctuation is stripped from normalised words`() {
        let parsed = ScriptParser.parse("(maybe).")
        #expect(parsed.normalisedWords == ["maybe"])
    }

    @Test func `tokens of pure punctuation normalise to empty strings`() {
        let parsed = ScriptParser.parse("yes -- no")
        #expect(parsed.normalisedWords == ["yes", "", "no"])
    }

    @Test func `punctuation is retained in the display text`() {
        let parsed = ScriptParser.parse("Hello, world!")
        #expect(parsed.displayWords.map(\.text) == ["Hello,", "world!"])
    }

    // MARK: - Apostrophes

    @Test func `straight apostrophes are preserved inside a word`() {
        let parsed = ScriptParser.parse("don't")
        #expect(parsed.normalisedWords == ["don't"])
    }

    @Test func `curly apostrophes are preserved inside a word`() {
        let parsed = ScriptParser.parse("don\u{2019}t")
        #expect(parsed.normalisedWords == ["don\u{2019}t"])
    }

    @Test func `multiple internal apostrophes are preserved`() {
        let parsed = ScriptParser.parse("rock'n'roll")
        #expect(parsed.normalisedWords == ["rock'n'roll"])
    }

    @Test func `leading and trailing apostrophes are stripped`() {
        let parsed = ScriptParser.parse("'twas 'brillig'")
        #expect(parsed.normalisedWords == ["twas", "brillig"])
    }

    // MARK: - Case

    @Test func `mixed case is lowercased in the normalised form`() {
        let parsed = ScriptParser.parse("MacBeth SLEEP")
        #expect(parsed.normalisedWords == ["macbeth", "sleep"])
    }

    @Test func `original case is retained in the display text`() {
        let parsed = ScriptParser.parse("MacBeth SLEEP")
        #expect(parsed.displayWords.map(\.text) == ["MacBeth", "SLEEP"])
    }

    @Test func `non-ASCII letters are lowercased`() {
        let parsed = ScriptParser.parse("Café")
        #expect(parsed.normalisedWords == ["café"])
    }

    // MARK: - Line breaks

    @Test func `a line break sets trailingNewlines on the preceding word`() {
        let parsed = ScriptParser.parse("first\nsecond")
        #expect(parsed.displayWords.first?.trailingNewlines == 1)
    }

    @Test func `a line break clears trailingSpace on the preceding word`() {
        let parsed = ScriptParser.parse("first\nsecond")
        #expect(parsed.displayWords.first?.trailingSpace == false)
    }

    @Test func `a space leaves trailingNewlines at zero`() {
        let parsed = ScriptParser.parse("first second")
        #expect(parsed.displayWords.first?.trailingNewlines == 0)
    }

    @Test func `a trailing newline at end of input sets trailingNewlines on the last word`() {
        let parsed = ScriptParser.parse("first\n")
        #expect(parsed.displayWords.last?.trailingNewlines == 1)
    }

    // MARK: - Stanza / blank-line breaks

    @Test func `a same-line space produces zero trailing newlines`() {
        let parsed = ScriptParser.parse("first second")
        #expect(parsed.displayWords.first?.trailingNewlines == 0)
    }

    @Test func `a single line break produces one trailing newline`() {
        let parsed = ScriptParser.parse("first\nsecond")
        #expect(parsed.displayWords.first?.trailingNewlines == 1)
    }

    @Test func `a blank line between two lines produces two trailing newlines`() {
        let parsed = ScriptParser.parse("first\n\nsecond")
        #expect(parsed.displayWords.first?.trailingNewlines == 2)
    }

    @Test func `multiple blank lines preserve the full newline count`() {
        let parsed = ScriptParser.parse("first\n\n\nsecond")
        #expect(parsed.displayWords.first?.trailingNewlines == 3)
    }

    @Test func `CRLF counts as a single line break`() {
        let parsed = ScriptParser.parse("first\r\nsecond")
        #expect(parsed.displayWords.first?.trailingNewlines == 1)
    }

    @Test func `a CRLF blank line counts as two line breaks`() {
        let parsed = ScriptParser.parse("first\r\n\r\nsecond")
        #expect(parsed.displayWords.first?.trailingNewlines == 2)
    }

    @Test func `a blank line does not change the normalised words`() {
        let parsed = ScriptParser.parse("first\n\nsecond")
        #expect(parsed.normalisedWords == ["first", "second"])
        #expect(parsed.displayWords.map(\.matchIndex) == [0, 1])
    }

    // MARK: - Empty and minimal input

    @Test func `empty input produces no display words`() {
        let parsed = ScriptParser.parse("")
        #expect(parsed.displayWords.isEmpty)
    }

    @Test func `empty input produces no normalised words`() {
        let parsed = ScriptParser.parse("")
        #expect(parsed.normalisedWords.isEmpty)
    }

    @Test func `whitespace-only input produces no words`() {
        let parsed = ScriptParser.parse("   \n\t  \n")
        #expect(parsed.displayWords.isEmpty)
    }

    @Test func `the supplied title is stored on the parsed script`() {
        let parsed = ScriptParser.parse("Hello.", title: "Greeting")
        #expect(parsed.title == "Greeting")
    }

    @Test func `the default title is empty`() {
        let parsed = ScriptParser.parse("Hello.")
        #expect(parsed.title == "")
    }

    @Test func `a single word produces exactly one display word`() {
        let parsed = ScriptParser.parse("Hello.")
        #expect(parsed.displayWords.count == 1)
    }

    @Test func `a single word has no trailing whitespace`() {
        let parsed = ScriptParser.parse("Hello.")
        let only = parsed.displayWords[0]
        #expect(!only.trailingSpace && !only.trailingNewline)
    }

    // MARK: - Performance smoke

    @Test func `parsing 1500 tokens completes within one second`() {
        let raw = (0..<1500).map { "Word\($0)," }.joined(separator: " ")
        let elapsed = ContinuousClock().measure {
            _ = ScriptParser.parse(raw)
        }
        #expect(elapsed < .seconds(1))
    }
}
