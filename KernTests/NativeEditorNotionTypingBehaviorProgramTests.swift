import AppKit
import XCTest
@testable import KernTextKit

final class NativeEditorNotionTypingBehaviorProgramTests: XCTestCase {
    private struct Scenario {
        let id: String
        let markdown: String
        let defaults: [String: Any]
    }

    private struct HybridInlineScenario {
        let id: String
        let markdown: String
        let visibleToken: String
        let expectedExportWithToken: (String) -> String
    }

    private struct ProtectedContextScenario {
        let id: String
        let markdown: String
        let defaults: [String: Any]
        let prepare: @MainActor (_ textView: NativeMarkdownTextView) -> Void
        let perform: @MainActor (_ vc: NativeEditorViewController, _ textView: NativeMarkdownTextView) -> Void
        let assertExport: (_ exported: String) -> Void
    }

    private enum Action: String {
        case newline
        case appendWord
        case backspaceCommand
        case markerSurgeryDelete
        case tabIndent
        case shiftTabOutdent
        case replaceBodyToken
        case pasteChecklist
        case undo
        case redo
    }

    @MainActor
    func testBehaviorProgramsAcrossListContexts_PRLane() {
        let scenarios: [Scenario] = [
            .init(id: "bullet", markdown: "- one\n", defaults: [:]),
            .init(id: "ordered", markdown: "1. one\n", defaults: [:]),
            .init(id: "task", markdown: "- [ ] one\n", defaults: [:]),
            .init(id: "nested-bullet", markdown: "1. parent\n   - child\n", defaults: [:]),
            .init(id: "nested-ordered", markdown: "1. parent\n   1. child\n", defaults: [:]),
            .init(id: "nested-task", markdown: "1. parent\n   - [ ] child\n", defaults: [:]),
            .init(
                id: "nested-ordered-task",
                markdown: "1. parent\n   1. [ ] child\n",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                    "nativeEditor.exportDialect": "gfm",
                ]
            ),
        ]

        let programs: [[Action]] = [
            [.newline, .appendWord, .tabIndent, .shiftTabOutdent, .appendWord],
            [.replaceBodyToken, .newline, .appendWord, .markerSurgeryDelete, .appendWord],
            [.pasteChecklist, .newline, .appendWord, .undo, .redo, .appendWord],
        ]

        for scenario in scenarios {
            withTemporaryDefaults(scenario.defaults) {
                for (programIndex, program) in programs.enumerated() {
                    let (vc, textView, window) = makeController(markdown: scenario.markdown)
                    defer { closeHostedEditor(window) }
                    moveCaretToEnd(textView)

                    for (step, action) in program.enumerated() {
                        apply(action: action, textView: textView, controller: vc, scenarioID: scenario.id, step: step)
                        drainMainRunLoop()
                        vc.flushPendingExport()
                        drainMainRunLoop()

                        let exported = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                        if let invariant = firstInvariantViolation(in: exported) {
                            XCTFail("[\(scenario.id)] [program=\(programIndex)] action=\(action.rawValue) invariant=\(invariant) export=\(exported)")
                            return
                        }
                    }

                    textView.insertText(" final-token", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertText("tail", replacementRange: textView.selectedRange())
                    drainMainRunLoop()
                    vc.flushPendingExport()
                    let finalExport = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                    XCTAssertTrue(finalExport.contains("final-token"), "[\(scenario.id)] [program=\(programIndex)] missing final token after program execution")
                    XCTAssertTrue(finalExport.contains("tail"), "[\(scenario.id)] [program=\(programIndex)] missing tail token after program execution")
                }
            }
        }
    }

    @MainActor
    func testMarkerSurgeryRecoveryAcrossListContexts_PRLane() {
        let scenarios: [Scenario] = [
            .init(id: "bullet", markdown: "- one\n", defaults: [:]),
            .init(id: "ordered", markdown: "1. one\n", defaults: [:]),
            .init(id: "task", markdown: "- [ ] one\n", defaults: [:]),
            .init(id: "nested-bullet", markdown: "1. parent\n   - child\n", defaults: [:]),
            .init(id: "nested-ordered", markdown: "1. parent\n   1. child\n", defaults: [:]),
            .init(id: "nested-task", markdown: "1. parent\n   - [ ] child\n", defaults: [:]),
            .init(
                id: "ordered-task",
                markdown: "1. [ ] one\n",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                    "nativeEditor.exportDialect": "gfm",
                ]
            ),
            .init(
                id: "nested-ordered-task",
                markdown: "1. parent\n   1. [ ] child\n",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                    "nativeEditor.exportDialect": "gfm",
                ]
            ),
        ]

        for scenario in scenarios {
            withTemporaryDefaults(scenario.defaults) {
                let (vc, textView, window) = makeController(markdown: scenario.markdown)
                defer { closeHostedEditor(window) }

                placeCaretAtBodyStart(in: textView)
                apply(action: .markerSurgeryDelete, textView: textView, controller: vc, scenarioID: scenario.id, step: 0)
                drainMainRunLoop()
                textView.insertText("repair-\(scenario.id)", replacementRange: textView.selectedRange())
                textView.insertNewline(nil)
                textView.insertText("tail-\(scenario.id)", replacementRange: textView.selectedRange())
                drainMainRunLoop()
                vc.flushPendingExport()

                let exported = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                XCTAssertTrue(exported.contains("repair-\(scenario.id)"), "[\(scenario.id)] expected typed recovery token after marker surgery. got=\(exported)")
                XCTAssertTrue(exported.contains("tail-\(scenario.id)"), "[\(scenario.id)] expected newline typing recovery after marker surgery. got=\(exported)")
                XCTAssertNil(firstInvariantViolation(in: exported), "[\(scenario.id)] invariant broken after marker surgery recovery. export=\(exported)")
            }
        }
    }

    @MainActor
    func testMixedListShortcutSwitchingScenarios_PRLane() {
        struct SwitchScenario {
            let id: String
            let markdown: String
            let shortcut: String
            let defaults: [String: Any]
            let requiredTokens: [String]
        }

        let scenarios: [SwitchScenario] = [
            .init(
                id: "ordered-to-bullet-task-nested",
                markdown: "1. parent\n   1. child\n",
                shortcut: "- [ ] ",
                defaults: [:],
                requiredTokens: ["parent", "child"]
            ),
            .init(
                id: "bullet-to-ordered-task-nested",
                markdown: "- parent\n  - child\n",
                shortcut: "1. [ ] ",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                    "nativeEditor.exportDialect": "gfm",
                ],
                requiredTokens: ["parent", "child"]
            ),
            .init(
                id: "ordered-task-to-bullet-task",
                markdown: "1. [ ] child\n",
                shortcut: "- [ ] ",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                    "nativeEditor.exportDialect": "gfm",
                ],
                requiredTokens: ["child"]
            ),
            .init(
                id: "task-to-ordered-task",
                markdown: "- [ ] child\n",
                shortcut: "1. [ ] ",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                    "nativeEditor.exportDialect": "gfm",
                ],
                requiredTokens: ["child"]
            ),
        ]

        for scenario in scenarios {
            withTemporaryDefaults(scenario.defaults) {
                let (vc, textView, window) = makeController(markdown: scenario.markdown)
                defer { closeHostedEditor(window) }

                placeCaretAtBodyStart(in: textView)
                textView.insertText(scenario.shortcut, replacementRange: textView.selectedRange())
                drainMainRunLoop()
                textView.insertNewline(nil)
                textView.insertText("next-\(scenario.id)", replacementRange: textView.selectedRange())
                drainMainRunLoop()
                vc.flushPendingExport()

                let exported = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                for token in scenario.requiredTokens {
                    XCTAssertTrue(exported.contains(token), "[\(scenario.id)] expected token '\(token)' to survive shortcut edits. got=\(exported)")
                }
                XCTAssertTrue(exported.contains("next-\(scenario.id)"), "[\(scenario.id)] expected typing continuation after switch. got=\(exported)")
                XCTAssertNil(firstInvariantViolation(in: exported), "[\(scenario.id)] invariant broken after list switch. export=\(exported)")
            }
        }
    }

    @MainActor
    func testPasteThenUndoRedoAcrossListContexts_PRLane() {
        let scenarios: [Scenario] = [
            .init(id: "bullet", markdown: "- one\n", defaults: [:]),
            .init(id: "ordered", markdown: "1. one\n", defaults: [:]),
            .init(id: "task", markdown: "- [ ] one\n", defaults: [:]),
            .init(
                id: "ordered-task",
                markdown: "1. [ ] one\n",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                    "nativeEditor.exportDialect": "gfm",
                ]
            ),
        ]

        for scenario in scenarios {
            withTemporaryDefaults(scenario.defaults) {
                let (vc, textView, window) = makeController(markdown: scenario.markdown)
                defer { closeHostedEditor(window) }

                moveCaretToEnd(textView)
                textView._debugPastePlainStringForTests("- [ ] pasted line\n")
                drainMainRunLoop()
                vc.flushPendingExport()

                var exported = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                XCTAssertTrue(exported.contains("pasted line"), "[\(scenario.id)] paste should insert semantic content")

                if let undoManager = textView.undoManager, undoManager.canUndo {
                    undoManager.undo()
                    drainMainRunLoop()
                    vc.flushPendingExport()
                }
                if let undoManager = textView.undoManager, undoManager.canRedo {
                    undoManager.redo()
                    drainMainRunLoop()
                    vc.flushPendingExport()
                }

                textView.insertText("after-paste", replacementRange: textView.selectedRange())
                textView.insertNewline(nil)
                textView.insertText("after-newline", replacementRange: textView.selectedRange())
                drainMainRunLoop()
                vc.flushPendingExport()

                exported = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                XCTAssertTrue(exported.contains("after-paste"), "[\(scenario.id)] typing should continue after paste/undo/redo")
                XCTAssertTrue(exported.contains("after-newline"), "[\(scenario.id)] newline typing should continue after paste/undo/redo")
                XCTAssertNil(firstInvariantViolation(in: exported), "[\(scenario.id)] invariant broken after paste/undo/redo. export=\(exported)")
            }
        }
    }

    @MainActor
    func testHybridInlineSpanExpandEditCollapsePrograms_PRLane() {
        let scenarios: [HybridInlineScenario] = [
            .init(
                id: "emphasis",
                markdown: "prefix *alpha* tail\n",
                visibleToken: "alpha",
                expectedExportWithToken: { "*\($0)*" }
            ),
            .init(
                id: "strong",
                markdown: "prefix **alpha** tail\n",
                visibleToken: "alpha",
                expectedExportWithToken: { "**\($0)**" }
            ),
            .init(
                id: "inline-code",
                markdown: "prefix `alpha` tail\n",
                visibleToken: "alpha",
                expectedExportWithToken: { "`\($0)`" }
            ),
            .init(
                id: "strikethrough",
                markdown: "prefix ~~alpha~~ tail\n",
                visibleToken: "alpha",
                expectedExportWithToken: { "~~\($0)~~" }
            ),
            .init(
                id: "inline-link-label",
                markdown: "prefix [alpha](https://example.com/docs) tail\n",
                visibleToken: "alpha",
                expectedExportWithToken: { "[\($0)](https://example.com/docs)" }
            ),
        ]

        withTemporaryDefaults([
            NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
        ]) {
            for scenario in scenarios {
                let (vc, textView, window) = makeController(markdown: scenario.markdown)
                defer { closeHostedEditor(window) }

                let visible = textView.string as NSString
                let tokenRange = visible.range(of: scenario.visibleToken)
                XCTAssertNotEqual(tokenRange.location, NSNotFound, "[\(scenario.id)] missing visible token before expansion")
                guard tokenRange.location != NSNotFound else { continue }

                textView.setSelectedRange(NSRange(location: tokenRange.location + 1, length: 0))
                drainMainRunLoop()

                let replacement = "edited-\(scenario.id)"
                let expanded = textView.string as NSString
                let expandedTokenRange = expanded.range(of: scenario.visibleToken)
                XCTAssertNotEqual(expandedTokenRange.location, NSNotFound, "[\(scenario.id)] missing token in expanded source")
                guard expandedTokenRange.location != NSNotFound else { continue }
                textView.insertText("", replacementRange: expandedTokenRange)
                textView.insertText(replacement, replacementRange: textView.selectedRange())
                drainMainRunLoop()

                moveCaretToEnd(textView)
                textView.insertText(" tail-\(scenario.id)", replacementRange: textView.selectedRange())
                textView.insertNewline(nil)
                textView.insertText("after-\(scenario.id)", replacementRange: textView.selectedRange())
                drainMainRunLoop()
                vc.flushPendingExport()

                let exported = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                XCTAssertTrue(
                    exported.contains(scenario.expectedExportWithToken(replacement)),
                    "[\(scenario.id)] expected edited inline syntax in export. got=\(exported)"
                )
                XCTAssertTrue(exported.contains("tail-\(scenario.id)"), "[\(scenario.id)] expected continuation token after collapse. got=\(exported)")
                XCTAssertTrue(exported.contains("after-\(scenario.id)"), "[\(scenario.id)] expected newline continuation token. got=\(exported)")
                XCTAssertNil(firstInvariantViolation(in: exported), "[\(scenario.id)] invariant broken after hybrid inline program. export=\(exported)")
            }
        }
    }

    @MainActor
    func testProtectedContextPrograms_PRLane() {
        let scenarios: [ProtectedContextScenario] = [
            .init(
                id: "code-fence-literal-markers",
                markdown: """
                ```
                seed
                ```

                after
                """,
                defaults: [:],
                prepare: { textView in
                    Self.moveCaretToSubstringEnd("seed", in: textView)
                },
                perform: { vc, textView in
                    textView.insertNewline(nil)
                    textView.insertText("- literal", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertText("1. still-literal", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertText("> quote-literal", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    textView.insertText(" tail-fence", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("```\nseed\n- literal\n1. still-literal\n> quote-literal\n```"), "Expected literal marker lines to remain inside the code fence. got=\(exported)")
                    XCTAssertTrue(exported.contains(" tail-fence"), "Expected plain-text continuation outside the fence. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- literal"), "Protected code-fence edits must not convert the document into a list. got=\(exported)")
                }
            ),
            .init(
                id: "table-cell-literal-markers",
                markdown: """
                | Name | Value |
                | --- | --- |
                | Alpha | Beta |
                """,
                defaults: [:],
                prepare: { textView in
                    Self.moveCaretToTableCellContentStart(row: 1, col: 0, in: textView)
                },
                perform: { vc, textView in
                    textView.insertText("- task ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToTableCellContentStart(row: 1, col: 1, in: textView)
                    textView.insertText("1. ordered-literal ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("| Name | Value |"), "Expected table header to remain intact. got=\(exported)")
                    XCTAssertTrue(exported.contains("| --- | --- |"), "Expected table separator row to remain intact. got=\(exported)")
                    XCTAssertTrue(exported.contains("- task Alpha"), "Expected literal bullet text to stay inside the first table cell. got=\(exported)")
                    XCTAssertTrue(exported.contains("1. ordered-literal Beta"), "Expected literal ordered-marker text to stay inside the second table cell. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- task Alpha"), "Protected table-cell edits must not convert the document into a list. got=\(exported)")
                }
            ),
            .init(
                id: "code-fence-history-preserves-literals",
                markdown: """
                ```
                seed
                ```

                after
                """,
                defaults: [:],
                prepare: { textView in
                    Self.moveCaretToSubstringEnd("seed", in: textView)
                },
                perform: { vc, textView in
                    textView.insertNewline(nil)
                    textView.insertText("- literal", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertText("1. ordered", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    textView.undoManager?.undo()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                    textView.undoManager?.redo()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    textView.insertText(" tail-history", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("```\nseed\n- literal\n1. ordered\n```"), "Expected undo/redo to preserve literal marker history inside the fence. got=\(exported)")
                    XCTAssertTrue(exported.contains(" tail-history"), "Expected typing to continue after leaving fenced history edits. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- literal"), "Fence history edits must not escape into a real list. got=\(exported)")
                }
            ),
            .init(
                id: "table-cell-history-preserves-structure",
                markdown: """
                | Name | Value |
                | --- | --- |
                | Alpha | Beta |
                """,
                defaults: [:],
                prepare: { textView in
                    Self.moveCaretToTableCellContentStart(row: 1, col: 0, in: textView)
                },
                perform: { vc, textView in
                    textView.insertText("- task ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    _ = vc.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    textView.insertText("1. ordered ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    textView.undoManager?.undo()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                    textView.undoManager?.redo()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    _ = vc.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:)))
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToTableCellContentStart(row: 1, col: 0, in: textView)
                    textView.insertText("tail ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("| Name | Value |"), "Expected table header to remain intact after history edits. got=\(exported)")
                    XCTAssertTrue(exported.contains("| --- | --- |"), "Expected table separator row to remain intact after history edits. got=\(exported)")
                    XCTAssertTrue(exported.contains("1. ordered Beta"), "Expected ordered shortcut history to stay inside the second table cell. got=\(exported)")
                    XCTAssertTrue(
                        exported.contains("tail - task Alpha") || exported.contains("- task tail Alpha") || exported.contains("- task Alpha tail"),
                        "Expected back/forward navigation to keep literal text in the first table cell. got=\(exported)"
                    )
                    XCTAssertFalse(exported.hasPrefix("- task"), "Table history edits must not convert the table into a list. got=\(exported)")
                }
            ),
            .init(
                id: "hybrid-inline-code-literal-markers",
                markdown: "`alpha`\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                prepare: { textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                },
                perform: { vc, textView in
                    Self.replaceVisibleToken("alpha", with: "- raw", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    textView.insertText(" tail-inline", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertText("after-inline", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("`- raw`"), "Expected literal marker text to remain inside inline code. got=\(exported)")
                    XCTAssertTrue(exported.contains(" tail-inline"), "Expected tail typing to continue after leaving inline code. got=\(exported)")
                    XCTAssertTrue(exported.contains("after-inline"), "Expected newline typing to continue after leaving inline code. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- raw"), "Protected inline-code edits must not convert the document into a list. got=\(exported)")
                }
            ),
            .init(
                id: "hybrid-link-destination-literal-markers",
                markdown: "[docs](dest-token)\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                prepare: { textView in
                    Self.moveCaretToSubstringStart("docs", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                },
                perform: { vc, textView in
                    textView.insertText("- ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    textView.insertText(" tail-link", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertText("after-link", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("[docs](- dest-token)") || exported.contains("[docs](- dest-token"),
                        "Expected literal marker text to remain inside the link destination. got=\(exported)"
                    )
                    XCTAssertTrue(exported.contains(" tail-link"), "Expected typing to continue after leaving the link literal. got=\(exported)")
                    XCTAssertTrue(exported.contains("after-link"), "Expected newline typing to continue after leaving the link literal. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- "), "Protected link-literal edits must not convert the document into a list. got=\(exported)")
                }
            ),
            .init(
                id: "reference-destination-literal-markers",
                markdown: """
                [docs]: dest-token

                [docs]
                """,
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.markdown.rawValue,
                ],
                prepare: { textView in
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                },
                perform: { vc, textView in
                    textView.insertText("- ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToLastSubstringStart("[docs]", in: textView)
                    textView.insertNewline(nil)
                    textView.insertText("after-reference", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("[docs]: - dest-token"), "Expected literal marker text to remain inside the reference definition. got=\(exported)")
                    XCTAssertTrue(exported.contains("after-reference"), "Expected continuation typing after leaving reference literal. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- "), "Protected reference-literal edits must not convert the document into a list. got=\(exported)")
                }
            ),
            .init(
                id: "reference-title-continuation-literal-markers",
                markdown: """
                [docs]: https://example.com
                  "title token"

                [docs]
                """,
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.markdown.rawValue,
                ],
                prepare: { textView in
                    Self.moveCaretToSubstringStart("title token", in: textView)
                },
                perform: { vc, textView in
                    textView.insertText("1. ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToLastSubstringEnd("[docs]", in: textView)
                    textView.insertNewline(nil)
                    textView.insertText("after-reference-title", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("[docs]: https://example.com"), "Expected reference definition head to survive. got=\(exported)")
                    XCTAssertTrue(
                        exported.contains(#""1. title token""#),
                        "Expected literal ordered marker text to remain inside the multiline reference title. got=\(exported)"
                    )
                    XCTAssertTrue(exported.contains("after-reference-title"), "Expected continuation typing after leaving multiline reference literal. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("1. "), "Protected multiline reference-title edits must not convert the document into a list. got=\(exported)")
                }
            ),
        ]

        for scenario in scenarios {
            withTemporaryDefaults(scenario.defaults) {
                let (vc, textView, window) = makeController(markdown: scenario.markdown)
                defer { closeHostedEditor(window) }

                scenario.prepare(textView)
                drainMainRunLoop()
                scenario.perform(vc, textView)
                drainMainRunLoop()

                let exported = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                scenario.assertExport(exported)
                XCTAssertNil(firstInvariantViolation(in: exported), "[\(scenario.id)] invariant broken after protected-context program. export=\(exported)")
            }
        }
    }

    @MainActor
    func testQuoteWrappedListBoundaryPrograms_PRLane() {
        let scenarios: [ProtectedContextScenario] = [
            .init(
                id: "quote-bullet-backspace-stays-quoted",
                markdown: "> - child",
                defaults: [:],
                prepare: { textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { vc, textView in
                    _ = vc.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    Self.moveCaretToSubstringEnd("child", in: textView)
                    textView.insertText(" repaired", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertText("quote-tail", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("after", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertNotNil(exported.range(of: #"\n?> child repaired"#, options: .regularExpression), "Expected bullet backspace to unlist within the quote, not escape it. got=\(exported)")
                    XCTAssertTrue(exported.contains("\n> quote-tail"), "Expected newline after quote-unlist to remain inside the quote. got=\(exported)")
                    XCTAssertTrue(exported.contains("\nafter"), "Expected double-enter to eventually exit back to top-level text. got=\(exported)")
                    XCTAssertNil(exported.range(of: #"\n- child"#, options: .regularExpression), "Quote-wrapped bullet should not survive as a list item after boundary backspace. got=\(exported)")
                }
            ),
            .init(
                id: "quote-ordered-second-enter-exits-list-before-quote",
                markdown: "> 1. item",
                defaults: [:],
                prepare: { textView in
                    Self.moveCaretToSubstringEnd("item", in: textView)
                },
                perform: { vc, textView in
                    textView.insertNewline(nil)
                    textView.insertText("continued", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("quote-tail", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("after", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("> 1. item"), "Expected initial ordered quote item to survive. got=\(exported)")
                    XCTAssertTrue(exported.contains("continued"), "Expected continued ordered content before exiting list. got=\(exported)")
                    XCTAssertTrue(exported.contains("\n> quote-tail"), "Expected second Enter to exit the list but keep the quote wrapper. got=\(exported)")
                    XCTAssertNil(exported.range(of: #"\n> \d+\. quote-tail"#, options: .regularExpression), "Expected quote-tail to be outside the ordered sub-list. got=\(exported)")
                    XCTAssertTrue(exported.contains("\nafter"), "Expected a later double-enter to exit back to top-level text. got=\(exported)")
                }
            ),
            .init(
                id: "quote-task-second-enter-exits-list-before-quote",
                markdown: "> - [ ] item",
                defaults: [
                    "nativeEditor.taskRendering": "gfm",
                ],
                prepare: { textView in
                    Self.moveCaretToSubstringEnd("item", in: textView)
                },
                perform: { vc, textView in
                    textView.insertNewline(nil)
                    textView.insertText("continued", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("quote-tail", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("after", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    vc.flushPendingExport()
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("> - [ ] item"), "Expected initial task quote item to survive. got=\(exported)")
                    XCTAssertTrue(exported.contains("> - [ ] continued"), "Expected continued task content before exiting list. got=\(exported)")
                    XCTAssertTrue(exported.contains("\n> quote-tail"), "Expected second Enter to exit the task list but keep the quote wrapper. got=\(exported)")
                    XCTAssertFalse(exported.contains("\n> - [ ] quote-tail"), "Expected quote-tail to be outside the task sub-list. got=\(exported)")
                    XCTAssertTrue(exported.contains("\nafter"), "Expected a later double-enter to exit back to top-level text. got=\(exported)")
                }
            ),
        ]

        for scenario in scenarios {
            withTemporaryDefaults(scenario.defaults) {
                let (vc, textView, window) = makeController(markdown: scenario.markdown)
                defer { closeHostedEditor(window) }

                scenario.prepare(textView)
                drainMainRunLoop()
                scenario.perform(vc, textView)
                drainMainRunLoop()

                let exported = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                scenario.assertExport(exported)
                XCTAssertNil(firstInvariantViolation(in: exported), "[\(scenario.id)] invariant broken after quote/list boundary program. export=\(exported)")
            }
        }
    }

    // MARK: - Action engine

    @MainActor
    private func apply(action: Action, textView: NativeMarkdownTextView, controller vc: NativeEditorViewController, scenarioID: String, step: Int) {
        switch action {
        case .newline:
            textView.insertNewline(nil)
        case .appendWord:
            textView.insertText(" w_\(scenarioID)_\(step)", replacementRange: textView.selectedRange())
        case .backspaceCommand:
            _ = vc.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
        case .markerSurgeryDelete:
            // Mimics "arrow into marker + delete" behavior repeatedly, then lets caller type/newline.
            for _ in 0..<3 {
                textView.moveLeft(nil)
                _ = vc.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
            }
        case .tabIndent:
            _ = vc.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
        case .shiftTabOutdent:
            _ = vc.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:)))
        case .replaceBodyToken:
            if let bodyRange = firstBodyTokenRange(in: textView.string as NSString) {
                textView.setSelectedRange(bodyRange)
                textView.insertText("swap", replacementRange: textView.selectedRange())
            } else {
                textView.insertText(" swap", replacementRange: textView.selectedRange())
            }
        case .pasteChecklist:
            textView._debugPastePlainStringForTests("- [ ] pasted-\(scenarioID)-\(step)\n")
        case .undo:
            textView.undoManager?.undo()
        case .redo:
            textView.undoManager?.redo()
        }
    }

    private func firstInvariantViolation(in exported: String) -> String? {
        if exported.contains("\u{0000}") {
            return "contains-nul"
        }
        if exported.contains("\n- []") || exported.contains("\n* []") || exported.contains("\n+ []") {
            return "malformed-task-marker"
        }
        if exported.contains("\n1.. ") {
            return "malformed-ordered-marker"
        }
        if exported.contains("[ ] ]") || exported.contains("[x] ]") || exported.contains("[X] ]") {
            return "malformed-bracket-balance"
        }
        return nil
    }

    private func firstBodyTokenRange(in ns: NSString) -> NSRange? {
        let candidates = ["child", "one", "parent", "task", "pasted", "w_"]
        for token in candidates {
            let range = ns.range(of: token)
            if range.location != NSNotFound { return range }
        }
        return nil
    }

    // MARK: - Shared test helpers

    @MainActor
    private func makeController(markdown: String) -> (NativeEditorViewController, NativeMarkdownTextView, NSWindow) {
        let vc = NativeEditorViewController()
        _ = vc.view
        vc.stringValue = markdown
        let window = hostInWindow(vc: vc, size: NSSize(width: 900, height: 650), appearance: .init(named: .darkAqua))
        window.displayIfNeeded()
        guard let textView = findTextView(in: vc.view) else {
            fatalError("Missing NativeEditor.TextView")
        }
        _ = window.makeFirstResponder(textView)
        drainMainRunLoop()
        return (vc, textView, window)
    }

    @MainActor
    private func hostInWindow(vc: NSViewController, size: NSSize, appearance: NSAppearance?) -> NSWindow {
        let rect = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.appearance = appearance
        window.contentViewController = vc
        window.setFrame(rect, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor
    private func closeHostedEditor(_ window: NSWindow) {
        window.orderOut(nil)
        window.close()
    }

    @MainActor
    private func findTextView(in view: NSView) -> NativeMarkdownTextView? {
        if let tv = view as? NativeMarkdownTextView { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }

    @MainActor
    private func moveCaretToEnd(_ textView: NSTextView) {
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    }

    @MainActor
    private static func moveCaretToSubstringStart(_ substring: String, in textView: NSTextView) {
        let ns = textView.string as NSString
        let range = ns.range(of: substring)
        XCTAssertNotEqual(range.location, NSNotFound, "Missing substring: \(substring)")
        if range.location == NSNotFound { return }
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
    }

    @MainActor
    private static func moveCaretToLastSubstringStart(_ substring: String, in textView: NSTextView) {
        let ns = textView.string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let range = ns.range(of: substring, options: .backwards, range: fullRange)
        XCTAssertNotEqual(range.location, NSNotFound, "Missing substring: \(substring)")
        if range.location == NSNotFound { return }
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
    }

    @MainActor
    private static func moveCaretToSubstringEnd(_ substring: String, in textView: NSTextView) {
        let ns = textView.string as NSString
        let range = ns.range(of: substring)
        XCTAssertNotEqual(range.location, NSNotFound, "Missing substring: \(substring)")
        if range.location == NSNotFound { return }
        textView.setSelectedRange(NSRange(location: range.location + range.length, length: 0))
    }

    @MainActor
    private static func moveCaretToLastSubstringEnd(_ substring: String, in textView: NSTextView) {
        let ns = textView.string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let range = ns.range(of: substring, options: .backwards, range: fullRange)
        XCTAssertNotEqual(range.location, NSNotFound, "Missing substring: \(substring)")
        if range.location == NSNotFound { return }
        textView.setSelectedRange(NSRange(location: range.location + range.length, length: 0))
    }

    @MainActor
    private static func moveCaretToTableCellContentStart(row: Int, col: Int, in textView: NativeMarkdownTextView) {
        guard let storage = textView.textStorage else {
            XCTFail("Missing text storage")
            return
        }
        let full = NSRange(location: 0, length: storage.length)
        var target: Int?
        storage.enumerateAttributes(in: full, options: []) { attrs, range, stop in
            let kindRaw = attrs[.kernBlockKind] as? Int
            let kind = KernBlockKind(rawValue: kindRaw ?? KernBlockKind.paragraph.rawValue) ?? .paragraph
            guard kind == .tableCell else { return }
            let r = attrs[.kernTableRow] as? Int ?? -1
            let c = attrs[.kernTableColumn] as? Int ?? -1
            guard r == row, c == col else { return }
            let ns = storage.string as NSString
            let paragraphRange = ns.paragraphRange(for: NSRange(location: range.location, length: 0))
            target = paragraphRange.location
            stop.pointee = true
        }
        guard let target else {
            XCTFail("Missing table cell row=\(row) col=\(col)")
            return
        }
        textView.setSelectedRange(NSRange(location: target, length: 0))
    }

    @MainActor
    private static func replaceVisibleToken(_ substring: String, with replacement: String, in textView: NSTextView) {
        let ns = textView.string as NSString
        let range = ns.range(of: substring)
        XCTAssertNotEqual(range.location, NSNotFound, "Missing substring: \(substring)")
        if range.location == NSNotFound { return }
        textView.insertText("", replacementRange: range)
        textView.insertText(replacement, replacementRange: textView.selectedRange())
    }

    @MainActor
    private func placeCaretAtBodyStart(in textView: NSTextView) {
        let ns = textView.string as NSString
        let candidates = ["child", "one", "alpha", "parent", "task"]
        for candidate in candidates {
            let range = ns.range(of: candidate)
            if range.location != NSNotFound {
                textView.setSelectedRange(NSRange(location: range.location, length: 0))
                return
            }
        }
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    }

    @MainActor
    private func drainMainRunLoop() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    private func withTemporaryDefaults<T>(_ overrides: [String: Any], _ body: () throws -> T) rethrows -> T {
        let defaults = UserDefaults.standard
        var effectiveOverrides = overrides
        if effectiveOverrides[NativeEditorSyntaxVisibilityMode.userDefaultsKey] == nil {
            effectiveOverrides[NativeEditorSyntaxVisibilityMode.userDefaultsKey] = NativeEditorSyntaxVisibilityMode.wysiwyg.rawValue
        }
        var saved: [String: Any?] = [:]
        for (key, value) in effectiveOverrides {
            saved[key] = defaults.object(forKey: key)
            defaults.set(value, forKey: key)
        }
        NotificationCenter.default.post(name: .nativeEditorPreferencesDidChange, object: nil)
        defer {
            for (key, previous) in saved {
                if let previous {
                    defaults.set(previous, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        return try body()
    }
}
