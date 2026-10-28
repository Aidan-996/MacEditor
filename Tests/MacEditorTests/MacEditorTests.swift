import Testing
import Foundation
@testable import MacEditor

// MARK: - FoldBuilder (indent-based code folding)

@Suite("FoldBuilder")
struct FoldBuilderTests {
    @Test func simpleSwiftFunctionFolds() {
        let text = """
        func foo() {
            let a = 1
            let b = 2
        }
        """
        let regions = FoldBuilder.regions(in: text, tabWidth: 4)
        #expect(regions.count == 1)
        #expect(regions[0].startLine == 1)
        #expect(regions[0].endLine == 3)
    }

    @Test func nestedBlocksProduceNestedRegions() {
        let text = """
        func outer() {
            if true {
                let x = 1
            }
            let y = 2
        }
        """
        let regions = FoldBuilder.regions(in: text, tabWidth: 4)
        // outer() spans lines 1-5, if-block spans lines 2-3.
        #expect(regions.contains { $0.startLine == 1 && $0.endLine == 5 })
        #expect(regions.contains { $0.startLine == 2 && $0.endLine == 3 })
    }

    @Test func flatLinesProduceNoRegions() {
        let text = "a\nb\nc"
        #expect(FoldBuilder.regions(in: text, tabWidth: 4).isEmpty)
    }

    @Test func blankLinesInsideBlockDoNotEndFold() {
        let text = """
        func foo() {
            let a = 1

            let b = 2
        }
        """
        let regions = FoldBuilder.regions(in: text, tabWidth: 4)
        #expect(regions.count == 1)
        #expect(regions[0].startLine == 1)
        #expect(regions[0].endLine == 4)
    }

    @Test func trailingBlankLineBeforeClosingBraceIsNotHidden() {
        // A blank line right before the closing brace must be trimmed from the
        // hidden range: folding should stop at the last real content line.
        let text = "func foo() {\n    let a = 1\n    let b = 2\n\n}"
        let regions = FoldBuilder.regions(in: text, tabWidth: 4)
        #expect(regions.count == 1)
        #expect(regions[0].startLine == 1)
        #expect(regions[0].endLine == 3) // "let b = 2", not the blank line or "}"
    }

    @Test func tabsCountAsTabWidthForIndent() {
        #expect(FoldBuilder.indent(of: "\tfoo", tabWidth: 4) == 4)
        #expect(FoldBuilder.indent(of: "  foo", tabWidth: 4) == 2)
        #expect(FoldBuilder.indent(of: "\t\tfoo", tabWidth: 2) == 4)
    }

    @Test func hiddenRangeCoversOnlyBodyNotHeader() {
        let text = "func foo() {\n    body\n}"
        let regions = FoldBuilder.regions(in: text, tabWidth: 4)
        let ns = text as NSString
        let hidden = regions[0].hiddenRange
        // The hidden range must start after the header line, i.e. not include "func foo() {".
        let headerRange = ns.lineRange(for: NSRange(location: 0, length: 0))
        #expect(hidden.location == NSMaxRange(headerRange))
    }
}

// MARK: - OutlineBuilder

@Suite("OutlineBuilder")
struct OutlineBuilderTests {
    @Test func markdownHeadings() {
        let text = """
        # Title
        intro
        ## Section A
        text
        ### Sub A.1
        """
        let items = OutlineBuilder.build(text: text, language: .markdown)
        #expect(items.map(\.title) == ["Title", "Section A", "Sub A.1"])
        #expect(items.map(\.depth) == [0, 1, 2])
        #expect(items.map(\.line) == [1, 3, 5])
    }

    @Test func markdownIgnoresHeadingsDeeperThanSix() {
        let text = "####### not a heading\n# real"
        let items = OutlineBuilder.build(text: text, language: .markdown)
        #expect(items.map(\.title) == ["real"])
    }

    @Test func swiftSymbols() {
        let text = """
        import Foundation

        struct Foo {
            func bar() {}
        }

        final class Baz {}
        """
        let items = OutlineBuilder.build(text: text, language: .swift)
        let names = items.map(\.title)
        #expect(names.contains("Foo"))
        #expect(names.contains("bar"))
        #expect(names.contains("Baz"))
    }

    @Test func pythonDefAndClass() {
        let text = """
        class Foo:
            def bar(self):
                pass

        def standalone():
            pass
        """
        let items = OutlineBuilder.build(text: text, language: .python)
        #expect(items.map(\.title) == ["Foo", "bar", "standalone"])
    }

    @Test func emptyTextProducesNoItems() {
        #expect(OutlineBuilder.build(text: "", language: .swift).isEmpty)
        #expect(OutlineBuilder.build(text: "", language: .markdown).isEmpty)
    }
}

// MARK: - FindMatchCounter

@Suite("FindMatchCounter")
struct FindMatchCounterTests {
    @Test func countsAllCaseInsensitiveMatches() {
        let text = "foo Foo FOO bar"
        let matches = FindMatchCounter.matches(in: text, query: "foo", regex: false)
        #expect(matches.count == 3)
    }

    @Test func emptyQueryProducesNoMatches() {
        #expect(FindMatchCounter.matches(in: "anything", query: "", regex: false).isEmpty)
    }

    @Test func regexMatches() {
        let text = "a1 b22 c333"
        let matches = FindMatchCounter.matches(in: text, query: #"\d+"#, regex: true)
        #expect(matches.count == 3)
    }

    @Test func invalidRegexReturnsNoMatchesInsteadOfCrashing() {
        let matches = FindMatchCounter.matches(in: "text", query: "(unclosed", regex: true)
        #expect(matches.isEmpty)
    }

    @Test func statusReturnsNilWithoutMatches() {
        #expect(FindMatchCounter.status(in: "abc", query: "xyz", caret: 0) == nil)
    }

    @Test func statusFindsCurrentIndexAtCaret() {
        let text = "foo bar foo bar foo"
        // Matches of "foo" are at locations 0, 8, 16.
        let status = FindMatchCounter.status(in: text, query: "foo", caret: 8)
        #expect(status != nil)
        #expect(status?.1 == 3) // total
        #expect(status?.0 == 2) // 1-based index of the match at location 8
    }
}

// MARK: - TextDocument encoding detection

@Suite("TextDocument.decode")
struct TextDocumentDecodeTests {
    @Test func utf8BOMIsStrippedAndDetected() {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let data = Data(bom) + "hello".data(using: .utf8)!
        let (text, enc) = TextDocument.decode(data)
        #expect(text == "hello")
        #expect(enc == .utf8)
    }

    @Test func utf16LittleEndianBOMDetected() {
        let data = "hello".data(using: .utf16LittleEndian)!
        let (text, enc) = TextDocument.decode(data)
        #expect(text == "hello")
        #expect(enc == .utf16LittleEndian)
    }

    @Test func plainASCIIDecodesAsUTF8() {
        let data = "plain ascii text".data(using: .utf8)!
        let (text, enc) = TextDocument.decode(data)
        #expect(text == "plain ascii text")
        #expect(enc == .utf8)
    }

    @Test func validUTF8CJKDecodesAsUTF8NotGB18030() {
        let data = "你好世界".data(using: .utf8)!
        let (text, enc) = TextDocument.decode(data)
        #expect(text == "你好世界")
        #expect(enc == .utf8)
    }

    @Test func gb18030OnlyBytesDecodeAsGB18030() throws {
        // Encode CJK text as GB18030; the byte stream is not valid UTF-8, so strict
        // UTF-8 decoding must fail and GB18030 must be picked.
        let gbData = try #require("你好，世界".data(using: .gb18030))
        let (text, enc) = TextDocument.decode(gbData)
        #expect(text == "你好，世界")
        #expect(enc == .gb18030)
    }

    @Test func emptyDataDecodesAsEmptyUTF8() {
        let (text, enc) = TextDocument.decode(Data())
        #expect(text == "")
        #expect(enc == .utf8)
    }

    @Test func forceDecodeAsISOLatin1NeverFails() {
        // ISO-8859-1 maps every byte 0x00-0xFF, so this must always succeed even on
        // bytes that are not valid UTF-8 or GB18030 (the "never lossy-replace" guarantee).
        let data = Data([0xFF, 0xFE, 0x00, 0x81, 0x90])
        #expect(TextDocument.decode(data, as: .isoLatin1) != nil)
    }

    @Test func normalizeLineEndingsDetectsCRLF() {
        let result = TextDocument.normalizeLineEndings("a\r\nb\r\nc")
        #expect(result.text == "a\nb\nc")
        #expect(result.ending == .crlf)
    }

    @Test func normalizeLineEndingsDetectsLF() {
        let result = TextDocument.normalizeLineEndings("a\nb\nc")
        #expect(result.text == "a\nb\nc")
        #expect(result.ending == .lf)
    }
}

// MARK: - TextStats (status bar word/char counts)

@Suite("TextStats")
struct TextStatsTests {
    @Test func asciiWordCount() {
        let (words, _) = TextStats.count("hello world foo")
        #expect(words == 3)
    }

    @Test func cjkCountsOnePerCharacter() {
        let (words, chars) = TextStats.count("你好世界")
        #expect(words == 4)
        #expect(chars == 4)
    }

    @Test func mixedCJKAndASCII() {
        let (words, _) = TextStats.count("你好 world")
        // 你, 好 = 2 words; "world" = 1 word.
        #expect(words == 3)
    }

    @Test func emptyStringHasZeroCounts() {
        let (words, chars) = TextStats.count("")
        #expect(words == 0)
        #expect(chars == 0)
    }
}

// MARK: - Language detection from file extension

@Suite("Language.detect")
struct LanguageTests {
    @Test func knownExtensionsMapToExpectedLanguage() {
        #expect(Language.detect(url: URL(fileURLWithPath: "a.swift")) == .swift)
        #expect(Language.detect(url: URL(fileURLWithPath: "a.py")) == .python)
        #expect(Language.detect(url: URL(fileURLWithPath: "a.md")) == .markdown)
        #expect(Language.detect(url: URL(fileURLWithPath: "a.csv")) == .plain)
        #expect(Language.detect(url: URL(fileURLWithPath: "a.tsv")) == .plain)
    }

    @Test func unknownExtensionFallsBackToPlain() {
        #expect(Language.detect(url: URL(fileURLWithPath: "a.zzz-not-a-real-ext")) == .plain)
    }

    @Test func nilURLFallsBackToPlain() {
        #expect(Language.detect(url: nil) == .plain)
    }
}
