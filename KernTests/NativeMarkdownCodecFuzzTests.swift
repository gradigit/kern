import Foundation
import XCTest
@testable import Kern

/// Deterministic fuzz tests that generate many small Markdown documents from seeds.
/// These are gated behind `KERN_ENABLE_EXHAUSTIVE_TESTS=1` to keep the default test run fast.
final class NativeMarkdownCodecFuzzTests: XCTestCase {
    @MainActor
    func testGeneratedMarkdownDoesNotCrashAndIsIdempotent() throws {
        try TestGates.skipUnlessExhaustive()

        let seeds: [UInt64] = [
            0x0000_0000_0000_0001,
            0x0123_4567_89AB_CDEF,
            0xDEAD_BEEF_CAFE_BABE,
            0xF00D_F00D_F00D_F00D,
            0xFACE_FEED_1234_5678,
        ]

        let optionsToTest: [NativeMarkdownCodec.Options] = {
            var list: [NativeMarkdownCodec.Options] = []
            list.append(.init())

            var kern = NativeMarkdownCodec.Options()
            kern.exportDialect = .kern
            kern.taskRendering = .kern
            kern.orderedTasksEnabled = true
            kern.headingCheckboxesEnabled = true
            kern.orderedListNumbering = .preserveTyped
            list.append(kern)

            var lint = NativeMarkdownCodec.Options()
            lint.exportDialect = .gfm
            lint.gfmExtensionExportStrategy = .lint
            lint.headingCheckboxesEnabled = true
            lint.orderedTasksEnabled = true
            list.append(lint)

            return list
        }()

        for seed in seeds {
            var rng = LCRNG(state: seed)
            let md = generateMarkdown(rng: &rng, lines: 240)

            try XCTContext.runActivity(named: "Seed: 0x\(String(seed, radix: 16))") { _ in
                for opt in optionsToTest {
                    let out1 = roundTrip(md, options: opt)
                    let out2 = roundTrip(out1, options: opt)
                    XCTAssertEqual(normalize(out1), normalize(out2), "Idempotency failed for seed=0x\(String(seed, radix: 16)) opt=\(describe(opt))")
                }
            }
        }
    }

    // MARK: - Generator

    private func generateMarkdown(rng: inout LCRNG, lines: Int) -> String {
        var out: [String] = []
        out.reserveCapacity(lines)

        var inCodeBlock = false
        var codeLinesLeft = 0

        for i in 0..<lines {
            if inCodeBlock {
                if codeLinesLeft == 0 {
                    out.append("```")
                    inCodeBlock = false
                    continue
                }
                codeLinesLeft -= 1
                out.append(randomCodeLine(rng: &rng))
                continue
            }

            // Occasionally insert blank lines to stress paragraph boundaries.
            if i % 23 == 0 || rng.oneIn(19) {
                out.append("")
                continue
            }

            let kind = rng.nextInt(10)
            switch kind {
            case 0:
                out.append(randomHeading(rng: &rng))
            case 1:
                out.append(randomBullet(rng: &rng))
            case 2:
                out.append(randomTask(rng: &rng))
            case 3:
                out.append(randomStandaloneTask(rng: &rng))
            case 4:
                out.append(randomOrdered(rng: &rng))
            case 5:
                // Code fence start
                out.append("```\(rng.oneIn(2) ? "js" : "")")
                inCodeBlock = true
                codeLinesLeft = 1 + rng.nextInt(8)
            default:
                out.append(randomParagraph(rng: &rng))
            }
        }

        // Close any unclosed code fence.
        if inCodeBlock {
            out.append("```")
        }

        return out.joined(separator: "\n") + "\n"
    }

    private func randomHeading(rng: inout LCRNG) -> String {
        let level = 1 + rng.nextInt(6)
        return String(repeating: "#", count: level) + " " + randomInline(rng: &rng)
    }

    private func randomBullet(rng: inout LCRNG) -> String {
        return "- " + randomInline(rng: &rng)
    }

    private func randomTask(rng: inout LCRNG) -> String {
        let checked = rng.oneIn(3)
        return "- [\(checked ? "x" : " ")] " + randomInline(rng: &rng)
    }

    private func randomStandaloneTask(rng: inout LCRNG) -> String {
        let checked = rng.oneIn(3)
        return "[\(checked ? "x" : " ")] " + randomInline(rng: &rng)
    }

    private func randomOrdered(rng: inout LCRNG) -> String {
        let n = 1 + rng.nextInt(20)
        return "\(n). " + randomInline(rng: &rng)
    }

    private func randomParagraph(rng: inout LCRNG) -> String {
        // Mix in escapes and long-ish lines.
        let parts = (0..<(3 + rng.nextInt(7))).map { _ in randomInline(rng: &rng) }
        var s = parts.joined(separator: " ")
        if rng.oneIn(5) { s += " \\\\" } // hard-break marker
        if rng.oneIn(7) { s += " \\* \\` \\[ \\]" }
        return s
    }

    private func randomInline(rng: inout LCRNG) -> String {
        let word = randomWord(rng: &rng)
        switch rng.nextInt(10) {
        case 0: return "**\(word)**"
        case 1: return "*\(word)*"
        case 2: return "`\(word)`"
        case 3: return "[\(word)](https://example.com/\(rng.nextInt(1000)))"
        default: return word
        }
    }

    private func randomWord(rng: inout LCRNG) -> String {
        let syllables = [
            "lo", "rem", "ip", "sum", "do", "lor", "sit", "a", "met",
            "kern", "md", "task", "code", "bold", "italic", "link",
            "edge", "case", "test", "perf", "bench",
        ]
        let n = 1 + rng.nextInt(4)
        var s = ""
        for _ in 0..<n {
            s += syllables[rng.nextInt(syllables.count)]
        }
        // Sprinkle some punctuation.
        if rng.oneIn(9) { s += "," }
        if rng.oneIn(19) { s += "." }
        return s
    }

    private func randomCodeLine(rng: inout LCRNG) -> String {
        let lines = [
            "console.log(\"hi\")",
            "let x = 1 + 2",
            "if (x > 2) { console.log(x) }",
            "function f(a) { return a * 2 }",
            "/* comment */",
        ]
        return lines[rng.nextInt(lines.count)]
    }

    // MARK: - Round-trip helpers

    @MainActor
    private func roundTrip(_ input: String, options: NativeMarkdownCodec.Options) -> String {
        let attr = NativeMarkdownCodec.importMarkdown(input, options: options)
        return NativeMarkdownCodec.exportMarkdown(attr, options: options)
    }

    private func describe(_ opt: NativeMarkdownCodec.Options) -> String {
        "dialect=\(opt.exportDialect.rawValue) gfmExt=\(opt.gfmExtensionExportStrategy.rawValue) taskRender=\(opt.taskRendering.rawValue) orderedTasks=\(opt.orderedTasksEnabled ? 1 : 0) headingTasks=\(opt.headingCheckboxesEnabled ? 1 : 0) orderedNum=\(opt.orderedListNumbering.rawValue)"
    }

    private func normalize(_ s: String) -> String {
        let lf = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = lf.split(separator: "\n", omittingEmptySubsequences: false)
        let trimmed = lines.map { $0.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression) }
        return trimmed.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}

// MARK: - Deterministic RNG

private struct LCRNG {
    var state: UInt64

    mutating func next() -> UInt64 {
        // 64-bit LCG (Numerical Recipes)
        state = 6364136223846793005 &* state &+ 1
        return state
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    mutating func oneIn(_ n: Int) -> Bool {
        precondition(n > 0)
        return nextInt(n) == 0
    }
}

