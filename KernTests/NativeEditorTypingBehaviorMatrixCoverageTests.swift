import AppKit
import XCTest
@testable import KernTextKit

final class NativeEditorTypingBehaviorMatrixCoverageTests: XCTestCase {
    private struct TransitionCase {
        let id: String
        let edge: TypingBehaviorEdge
        let seedMarkdown: String
        let defaults: [String: Any]
        let explicitMarkerState: TypingBehaviorMarkerState?
        let explicitIndentBucket: TypingBehaviorIndentBucket?
        let explicitContentState: TypingBehaviorContentState?
        let explicitPolicyProfile: TypingBehaviorPolicyProfile?
        let explicitShortcutVariant: TypingBehaviorShortcutVariant?
        let prepare: @MainActor (_ vc: NativeEditorViewController, _ textView: NativeMarkdownTextView) -> Void
        let perform: @MainActor (_ vc: NativeEditorViewController, _ textView: NativeMarkdownTextView) -> Void
        let assertExport: (_ exported: String) -> Void

        init(
            id: String,
            edge: TypingBehaviorEdge,
            seedMarkdown: String,
            defaults: [String: Any],
            markerState: TypingBehaviorMarkerState? = nil,
            indentBucket: TypingBehaviorIndentBucket? = nil,
            contentState: TypingBehaviorContentState? = nil,
            policyProfile: TypingBehaviorPolicyProfile? = nil,
            shortcutVariant: TypingBehaviorShortcutVariant? = nil,
            prepare: @escaping @MainActor (_ vc: NativeEditorViewController, _ textView: NativeMarkdownTextView) -> Void,
            perform: @escaping @MainActor (_ vc: NativeEditorViewController, _ textView: NativeMarkdownTextView) -> Void,
            assertExport: @escaping (_ exported: String) -> Void
        ) {
            self.id = id
            self.edge = edge
            self.seedMarkdown = seedMarkdown
            self.defaults = defaults
            self.explicitMarkerState = markerState
            self.explicitIndentBucket = indentBucket
            self.explicitContentState = contentState
            self.explicitPolicyProfile = policyProfile
            self.explicitShortcutVariant = shortcutVariant
            self.prepare = prepare
            self.perform = perform
            self.assertExport = assertExport
        }

        var factors: TypingBehaviorFactors {
            TypingBehaviorFactors(
                context: edge.context,
                action: edge.action,
                markerState: explicitMarkerState ?? .default(for: edge.context),
                indentBucket: explicitIndentBucket ?? .default(for: edge.context),
                contentState: explicitContentState ?? .nonEmpty,
                policyProfile: explicitPolicyProfile ?? .default(for: edge.context),
                shortcutVariant: explicitShortcutVariant ?? .default(for: edge.action)
            )
        }
    }

    @MainActor
    func testCriticalTypingBehaviorTransitionMatrix_PRLane() throws {
        let cases = prLaneCases()
        var coverage = TypingBehaviorCoverage(contract: .current())

        for c in cases {
            withTemporaryDefaults(c.defaults) {
                let (vc, textView, window) = makeController(markdown: c.seedMarkdown)
                defer { closeHostedEditor(window) }

                c.prepare(vc, textView)
                c.perform(vc, textView)
                drainMainRunLoop()
                vc.flushPendingExport()
                drainMainRunLoop()

                let exported = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                c.assertExport(exported)
                coverage.record(factors: c.factors, caseID: c.id)
            }
        }

        let coverageReport = coverage.renderReport()
        attachReport(coverageReport, name: "typing-behavior-matrix-coverage")
        print(coverageReport)
        let missingFactors = coverage.missingRequiredFactors
        XCTAssertTrue(
            missingFactors.isEmpty,
            "Missing required factor cases: \(missingFactors.map(\.label).joined(separator: ", "))"
        )
        XCTAssertGreaterThanOrEqual(
            coverage.pairwiseCoverageRatio,
            coverage.contract.lane.pairwiseThreshold,
            "Pairwise coverage below threshold for lane=\(coverage.contract.lane.rawValue): \(coverage.pairwiseCoverageRatio)"
        )
        if let tripleThreshold = coverage.contract.lane.criticalTripleThreshold {
            XCTAssertGreaterThanOrEqual(
                coverage.criticalTripleCoverageRatio,
                tripleThreshold,
                "Critical triple coverage below threshold for lane=\(coverage.contract.lane.rawValue): \(coverage.criticalTripleCoverageRatio)"
            )
        }
    }

    // MARK: - Matrix Cases

    @MainActor
    private func prLaneCases() -> [TransitionCase] {
        var out: [TransitionCase] = []

        out.append(
            TransitionCase(
                id: "paragraph-marker-bullet",
                edge: TypingBehaviorEdge(context: .paragraph, action: .markerShortcut),
                seedMarkdown: "",
                defaults: [:],
                contentState: .empty,
                shortcutVariant: .bullet,
                prepare: { _, _ in },
                perform: { _, textView in
                    textView.insertText("- ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.hasPrefix("- "), "Expected bullet marker shortcut export. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "paragraph-marker-ordered",
                edge: TypingBehaviorEdge(context: .paragraph, action: .markerShortcut),
                seedMarkdown: "",
                defaults: [:],
                contentState: .empty,
                shortcutVariant: .ordered,
                prepare: { _, _ in },
                perform: { _, textView in
                    textView.insertText("1. ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("1. "), "Expected ordered marker shortcut export. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "paragraph-marker-star-bullet",
                edge: TypingBehaviorEdge(context: .paragraph, action: .markerShortcut),
                seedMarkdown: "",
                defaults: [:],
                contentState: .empty,
                shortcutVariant: .bullet,
                prepare: { _, _ in },
                perform: { _, textView in
                    textView.insertText("* ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("* ") || exported.contains("- "), "Expected star marker shortcut export. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "paragraph-marker-plus-bullet",
                edge: TypingBehaviorEdge(context: .paragraph, action: .markerShortcut),
                seedMarkdown: "",
                defaults: [:],
                contentState: .empty,
                shortcutVariant: .bullet,
                prepare: { _, _ in },
                perform: { _, textView in
                    textView.insertText("+ ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("+ ") || exported.contains("- "), "Expected plus marker shortcut export. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "paragraph-marker-task",
                edge: TypingBehaviorEdge(context: .paragraph, action: .markerShortcut),
                seedMarkdown: "",
                defaults: [
                    "nativeEditor.taskRendering": "gfm",
                ],
                contentState: .empty,
                shortcutVariant: .task,
                prepare: { _, _ in },
                perform: { _, textView in
                    textView.insertText("- [ ] ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("- [ ] ") || exported.contains("- ☐ "),
                        "Expected task marker shortcut export. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "paragraph-marker-quote",
                edge: TypingBehaviorEdge(context: .paragraph, action: .markerShortcut),
                seedMarkdown: "",
                defaults: [:],
                contentState: .empty,
                shortcutVariant: .quote,
                prepare: { _, _ in },
                perform: { _, textView in
                    textView.insertText("> ", replacementRange: textView.selectedRange())
                    textView.insertText("quoted", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("> quoted"), "Expected blockquote shortcut export. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "bullet-enter-continue",
                edge: TypingBehaviorEdge(context: .bullet, action: .enter),
                seedMarkdown: "- alpha",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("beta", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("- alpha"))
                    XCTAssertTrue(exported.contains("- beta"), "Expected bullet continuation line. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-enter-continue",
                edge: TypingBehaviorEdge(context: .ordered, action: .enter),
                seedMarkdown: "1. alpha",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("beta", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("1. alpha"))
                    XCTAssertTrue(exported.contains("beta"), "Expected ordered continuation content. got=\(exported)")
                    XCTAssertTrue(
                        exported.contains("2. beta") || exported.contains("1. beta"),
                        "Expected ordered continuation marker. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "bullet-second-enter-exit",
                edge: TypingBehaviorEdge(context: .bullet, action: .secondEnterExit),
                seedMarkdown: "- alpha",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("after", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("- alpha"))
                    XCTAssertTrue(exported.contains("after"))
                    XCTAssertFalse(exported.contains("- after"), "Expected second Enter to exit bullet context. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-second-enter-exit",
                edge: TypingBehaviorEdge(context: .ordered, action: .secondEnterExit),
                seedMarkdown: "1. alpha",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("after", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("1. alpha"))
                    XCTAssertTrue(exported.contains("after"))
                    XCTAssertFalse(exported.contains("2. after"), "Expected second Enter to exit ordered context. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-marker-shortcut-switch-to-bullet",
                edge: TypingBehaviorEdge(context: .ordered, action: .markerShortcut),
                seedMarkdown: "1. alpha\n",
                defaults: [:],
                shortcutVariant: .bullet,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { _, textView in
                    textView.insertText("-", replacementRange: textView.selectedRange())
                    textView.insertText(" ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertEqual(exported, "- alpha\n")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "bullet-tab-indent",
                edge: TypingBehaviorEdge(context: .bullet, action: .tabIndent),
                seedMarkdown: "- alpha\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
                },
                assertExport: { exported in
                    XCTAssertEqual(exported, "  - alpha\n")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "bullet-shift-tab-outdent",
                edge: TypingBehaviorEdge(context: .bullet, action: .shiftTabOutdent),
                seedMarkdown: "  - alpha\n",
                defaults: [:],
                indentBucket: .nested,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
                },
                assertExport: { exported in
                    XCTAssertEqual(exported, "- alpha\n")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-tab-indent",
                edge: TypingBehaviorEdge(context: .ordered, action: .tabIndent),
                seedMarkdown: "1. alpha\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
                },
                assertExport: { exported in
                    XCTAssertEqual(exported, "   1. alpha\n")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-shift-tab-outdent",
                edge: TypingBehaviorEdge(context: .ordered, action: .shiftTabOutdent),
                seedMarkdown: "   1. alpha\n",
                defaults: [:],
                indentBucket: .nested,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
                },
                assertExport: { exported in
                    XCTAssertEqual(exported, "1. alpha\n")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "task-tab-indent",
                edge: TypingBehaviorEdge(context: .task, action: .tabIndent),
                seedMarkdown: "- [ ] alpha\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
                },
                assertExport: { exported in
                    XCTAssertEqual(exported, "  - [ ] alpha\n")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "task-shift-tab-outdent",
                edge: TypingBehaviorEdge(context: .task, action: .shiftTabOutdent),
                seedMarkdown: "  - [ ] alpha\n",
                defaults: [:],
                indentBucket: .nested,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
                },
                assertExport: { exported in
                    XCTAssertEqual(exported, "- [ ] alpha\n")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-ordered-enter-continue",
                edge: TypingBehaviorEdge(context: .nestedOrdered, action: .enter),
                seedMarkdown: "1. parent\n   1. child",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("next", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("1. parent"))
                    XCTAssertTrue(exported.contains("1. child"))
                    XCTAssertTrue(
                        exported.contains("2. next") || exported.contains("1. next"),
                        "Expected nested ordered continuation marker. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-ordered-shift-tab-outdent",
                edge: TypingBehaviorEdge(context: .nestedOrdered, action: .shiftTabOutdent),
                seedMarkdown: "1. parent\n   1. child\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("1. child") || exported.contains("2. child"),
                        "Expected nested ordered Shift+Tab to keep ordered marker while outdenting. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-task-tab-indent",
                edge: TypingBehaviorEdge(context: .nestedTask, action: .tabIndent),
                seedMarkdown: "1. parent\n   - [ ] child\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
                },
                assertExport: { exported in
                    XCTAssertFalse(exported.contains("```"), "Nested task tab-indent should not degrade into code block. got=\(exported)")
                    XCTAssertTrue(exported.contains("- [ ] child"), "Expected nested task marker retained after indent. got=\(exported)")
                    XCTAssertTrue(exported.contains("child"), "Expected content to remain editable after nested task indent. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-bullet-shift-tab-outdent",
                edge: TypingBehaviorEdge(context: .nestedBullet, action: .shiftTabOutdent),
                seedMarkdown: "1. parent\n     - child\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("  - child") || exported.contains("- child"),
                        "Expected nested bullet outdent. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-task-shift-tab-outdent",
                edge: TypingBehaviorEdge(context: .nestedTask, action: .shiftTabOutdent),
                seedMarkdown: "1. parent\n     - [ ] child\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("   - [ ] child") || exported.contains("- [ ] child"),
                        "Expected nested task outdent. got=\(exported)"
                    )
                    XCTAssertFalse(exported.contains("```"), "Nested task outdent should remain a list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-ordered-marker-shortcut-to-bullet-task",
                edge: TypingBehaviorEdge(context: .nestedOrdered, action: .markerShortcut),
                seedMarkdown: "1. parent\n   1. child\n",
                defaults: [:],
                shortcutVariant: .task,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { _, textView in
                    textView.insertText("- [ ] ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("   - [ ] child") || exported.contains("   - ☐ child"),
                        "Expected nested ordered -> nested bullet task conversion. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-task-marker-shortcut-to-ordered-task",
                edge: TypingBehaviorEdge(context: .nestedTask, action: .markerShortcut),
                seedMarkdown: "1. parent\n   - [ ] child\n",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                ],
                shortcutVariant: .ordered,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { _, textView in
                    textView.insertText("1. [ ] ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("   1. [ ] child") || exported.contains("   1. ☐ child"),
                        "Expected nested task -> nested ordered task conversion. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-task-marker-delete-recovery",
                edge: TypingBehaviorEdge(context: .nestedTask, action: .backspaceAtBoundary),
                seedMarkdown: "1. parent\n   - [ ] child\n",
                defaults: [:],
                prepare: { _, textView in
                    guard let storage = textView.textStorage else { return }
                    let ns = storage.string as NSString
                    let childRange = ns.range(of: "child")
                    guard childRange.location != NSNotFound else {
                        XCTFail("Missing nested task body")
                        return
                    }
                    let childPara = ns.paragraphRange(for: NSRange(location: childRange.location, length: 0))
                    var nestedMarker: Int?
                    storage.enumerateAttribute(.kernMarker, in: childPara, options: []) { value, range, stop in
                        if (value as? Bool) == true {
                            nestedMarker = range.location
                            stop.pointee = true
                        }
                    }
                    guard let marker = nestedMarker else {
                        XCTFail("Missing nested task marker")
                        return
                    }
                    textView.insertText("", replacementRange: NSRange(location: marker, length: 1))
                    textView.setSelectedRange(NSRange(location: marker, length: 0))
                },
                perform: { _, textView in
                    textView.insertText("z", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    textView.insertNewline(nil)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    textView.insertText("next", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("z"), "Expected typing recovery after nested task marker edit. got=\(exported)")
                    XCTAssertTrue(exported.contains("next"), "Expected newline recovery after nested task marker edit. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-task-enter-continue",
                edge: TypingBehaviorEdge(context: .orderedTask, action: .enter),
                seedMarkdown: "1. [ ] alpha",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                ],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("beta", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("1. [ ] alpha") || exported.contains("1. ☐ alpha"))
                    XCTAssertTrue(
                        exported.contains("2. [ ] beta") || exported.contains("2. ☐ beta") || exported.contains("1. [ ] beta"),
                        "Expected ordered-task continuation line. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-task-tab-indent",
                edge: TypingBehaviorEdge(context: .orderedTask, action: .tabIndent),
                seedMarkdown: "1. [ ] alpha\n",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                ],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("   1. [ ] alpha") || exported.contains("   1. ☐ alpha"),
                        "Expected ordered-task indent via tab. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-task-shift-tab-outdent",
                edge: TypingBehaviorEdge(context: .orderedTask, action: .shiftTabOutdent),
                seedMarkdown: "   1. [ ] alpha\n",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                ],
                indentBucket: .nested,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("1. [ ] alpha") || exported.contains("1. ☐ alpha"),
                        "Expected ordered-task outdent via Shift+Tab. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-task-space-toggle",
                edge: TypingBehaviorEdge(context: .orderedTask, action: .spaceToggle),
                seedMarkdown: "1. [ ] task",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                ],
                prepare: { _, textView in
                    guard let storage = textView.textStorage,
                          let checkboxIndex = Self.firstCheckboxIndex(in: storage, range: NSRange(location: 0, length: storage.length)) else {
                        XCTFail("Expected ordered-task checkbox marker")
                        return
                    }
                    textView.setSelectedRange(NSRange(location: checkboxIndex, length: 0))
                },
                perform: { _, textView in
                    textView.insertText(" ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("1. [x] task") || exported.contains("1. [X] task") || exported.contains("1. ☑ task"),
                        "Expected ordered-task checkbox toggle. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-task-second-enter-exit",
                edge: TypingBehaviorEdge(context: .orderedTask, action: .secondEnterExit),
                seedMarkdown: "1. [ ] alpha",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                ],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("after", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("1. [ ] alpha") || exported.contains("1. ☐ alpha"))
                    XCTAssertTrue(exported.contains("after"))
                    XCTAssertFalse(exported.contains("2. [ ] after"), "Expected second Enter to exit ordered-task context. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-ordered-task-enter-continue",
                edge: TypingBehaviorEdge(context: .nestedOrderedTask, action: .enter),
                seedMarkdown: "1. parent\n   1. [ ] child",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                ],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("next", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("   1. [ ] child") || exported.contains("   1. ☐ child"),
                        "Expected nested ordered task baseline. got=\(exported)"
                    )
                    XCTAssertTrue(
                        exported.contains("2. [ ] next") || exported.contains("2. ☐ next") || exported.contains("1. [ ] next"),
                        "Expected nested ordered task continuation marker. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-ordered-task-tab-indent",
                edge: TypingBehaviorEdge(context: .nestedOrderedTask, action: .tabIndent),
                seedMarkdown: "1. parent\n   1. [ ] child\n",
                defaults: [
                    "nativeEditor.orderedTasksEnabled": true,
                    "nativeEditor.taskRendering": "gfm",
                ],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { vc, textView in
                    XCTAssertTrue(vc.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
                },
                assertExport: { exported in
                    XCTAssertFalse(exported.contains("```"), "Nested ordered-task indent should remain list content. got=\(exported)")
                    XCTAssertTrue(
                        exported.contains("1. [ ] child") || exported.contains("1. ☐ child"),
                        "Expected nested ordered task marker retained after indent. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "heading-task-enter-then-bullet-task",
                edge: TypingBehaviorEdge(context: .headingTask, action: .enter),
                seedMarkdown: "## [ ] Heading task",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("- [ ] child", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("## [ ] Heading task") || exported.contains("## ☐ Heading task"),
                        "Expected heading task retained. got=\(exported)"
                    )
                    XCTAssertTrue(
                        exported.contains("- [ ] child") || exported.contains("- ☐ child"),
                        "Expected bullet task creation after heading-task newline. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-ordered-marker-delete-recovery",
                edge: TypingBehaviorEdge(context: .nestedOrdered, action: .backspaceAtBoundary),
                seedMarkdown: "1. parent\n   1. child\n",
                defaults: [:],
                prepare: { _, textView in
                    guard let storage = textView.textStorage else { return }
                    guard let markerIndex = Self.firstMarkerIndex(in: storage, range: NSRange(location: 0, length: storage.length)) else {
                        XCTFail("Expected list marker")
                        return
                    }
                    let ns = storage.string as NSString
                    let second = ns.range(of: "child")
                    guard second.location != NSNotFound else {
                        XCTFail("Missing nested ordered body")
                        return
                    }
                    let secondPara = ns.paragraphRange(for: NSRange(location: second.location, length: 0))
                    var nestedMarker: Int?
                    storage.enumerateAttribute(.kernMarker, in: secondPara, options: []) { value, range, stop in
                        if (value as? Bool) == true {
                            nestedMarker = range.location
                            stop.pointee = true
                        }
                    }
                    let targetMarker = nestedMarker ?? markerIndex
                    textView.insertText("", replacementRange: NSRange(location: targetMarker, length: 1))
                    textView.setSelectedRange(NSRange(location: targetMarker, length: 0))
                },
                perform: { _, textView in
                    textView.insertText("z", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    textView.insertNewline(nil)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    textView.insertText("next", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("z"), "Expected typing recovery after nested marker delete. got=\(exported)")
                    XCTAssertTrue(exported.contains("next"), "Expected newline recovery after nested marker delete. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-bullet-backspace-outdent",
                edge: TypingBehaviorEdge(context: .nestedBullet, action: .backspaceAtBoundary),
                seedMarkdown: "1. parent\n   - child\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { vc, textView in
                    _ = vc.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("  - child") || exported.contains("- child"),
                        "Expected nested bullet backspace to outdent first. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "nested-ordered-backspace-outdent",
                edge: TypingBehaviorEdge(context: .nestedOrdered, action: .backspaceAtBoundary),
                seedMarkdown: "1. parent\n   1. child\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("child", in: textView)
                },
                perform: { vc, textView in
                    _ = vc.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("1. child") || exported.contains("2. child"),
                        "Expected nested ordered backspace to keep ordered marker while outdenting. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "task-space-toggle",
                edge: TypingBehaviorEdge(context: .task, action: .spaceToggle),
                seedMarkdown: "- [ ] task",
                defaults: [:],
                prepare: { _, textView in
                    guard let storage = textView.textStorage,
                          let checkboxIndex = Self.firstCheckboxIndex(in: storage, range: NSRange(location: 0, length: storage.length)) else {
                        XCTFail("Expected checkbox marker")
                        return
                    }
                    textView.setSelectedRange(NSRange(location: checkboxIndex, length: 0))
                },
                perform: { _, textView in
                    textView.insertText(" ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("- [x] task") || exported.contains("- [X] task"),
                        "Expected toggled task checkbox. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "task-enter-continue",
                edge: TypingBehaviorEdge(context: .task, action: .enter),
                seedMarkdown: "- [ ] one",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("two", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("- [ ] one"))
                    XCTAssertTrue(exported.contains("- [ ] two"), "Expected task continuation line. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "task-second-enter-exit",
                edge: TypingBehaviorEdge(context: .task, action: .secondEnterExit),
                seedMarkdown: "- [ ] one",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("after", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("- [ ] one") || exported.contains("- ☐ one"))
                    XCTAssertTrue(exported.contains("after"))
                    XCTAssertFalse(exported.contains("- [ ] after"), "Expected second Enter to exit task context. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "quote-enter-continue",
                edge: TypingBehaviorEdge(context: .quote, action: .enter),
                seedMarkdown: "> quote",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("continued", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("> quote"))
                    XCTAssertTrue(exported.contains("> continued"), "Expected quote continuation marker. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "quote-second-enter-exit",
                edge: TypingBehaviorEdge(context: .quote, action: .secondEnterExit),
                seedMarkdown: "> quote",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("continued", replacementRange: textView.selectedRange())
                    textView.insertNewline(nil)
                    textView.insertNewline(nil)
                    textView.insertText("after", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("> quote"))
                    XCTAssertTrue(exported.contains("> continued"))
                    XCTAssertTrue(exported.contains("after"))
                    XCTAssertFalse(exported.contains("\n> \n"), "Second Enter should exit quote context. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "codefence-bullet-shortcut-no-convert",
                edge: TypingBehaviorEdge(context: .codeFence, action: .markerShortcut),
                seedMarkdown: "```\ncode\n```",
                defaults: [:],
                shortcutVariant: .bullet,
                prepare: { _, textView in
                    Self.moveCaretToSubstringEnd("code", in: textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("- raw-bullet", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("```"))
                    XCTAssertTrue(exported.contains("- raw-bullet"), "Expected bullet shortcut text to remain literal inside code fence. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- raw-bullet"), "Code fence bullet shortcut must not escape into a real list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "codefence-ordered-shortcut-no-convert",
                edge: TypingBehaviorEdge(context: .codeFence, action: .markerShortcut),
                seedMarkdown: "```\ncode\n```",
                defaults: [:],
                shortcutVariant: .ordered,
                prepare: { _, textView in
                    Self.moveCaretToSubstringEnd("code", in: textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("1. raw-ordered", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("```"))
                    XCTAssertTrue(exported.contains("1. raw-ordered"), "Expected ordered shortcut text to remain literal inside code fence. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("1. raw-ordered"), "Code fence ordered shortcut must not escape into a real list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "codefence-marker-shortcut-no-convert",
                edge: TypingBehaviorEdge(context: .codeFence, action: .markerShortcut),
                seedMarkdown: "```\ncode\n```",
                defaults: [:],
                shortcutVariant: .task,
                prepare: { _, textView in
                    Self.moveCaretToSubstringEnd("code", in: textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("- [ ] raw", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("```"))
                    XCTAssertTrue(exported.contains("- [ ] raw"), "Expected raw markdown to remain literal inside code fence. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "codefence-quote-shortcut-no-convert",
                edge: TypingBehaviorEdge(context: .codeFence, action: .markerShortcut),
                seedMarkdown: "```\ncode\n```",
                defaults: [:],
                shortcutVariant: .quote,
                prepare: { _, textView in
                    Self.moveCaretToSubstringEnd("code", in: textView)
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    textView.insertText("> raw-quote", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("```"))
                    XCTAssertTrue(exported.contains("> raw-quote"), "Expected quote shortcut text to remain literal inside code fence. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("> raw-quote"), "Code fence quote shortcut must not escape into a real blockquote. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "table-cell-marker-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .tableCell, action: .markerShortcut),
                seedMarkdown: """
                | Name | Value |
                | --- | --- |
                | Alpha | Beta |
                """,
                defaults: [:],
                shortcutVariant: .bullet,
                prepare: { _, textView in
                    Self.moveCaretToTableCellContentStart(row: 1, col: 0, in: textView)
                },
                perform: { _, textView in
                    textView.insertText("- ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("| --- | --- |"), "Expected table structure to remain intact. got=\(exported)")
                    XCTAssertTrue(exported.contains("- Alpha"), "Expected table cell content to keep literal marker text. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- Alpha"), "Table cell shortcut must not convert the row into a bullet block. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "table-cell-ordered-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .tableCell, action: .markerShortcut),
                seedMarkdown: """
                | Name | Value |
                | --- | --- |
                | Alpha | Beta |
                """,
                defaults: [:],
                shortcutVariant: .ordered,
                prepare: { _, textView in
                    Self.moveCaretToTableCellContentStart(row: 1, col: 0, in: textView)
                },
                perform: { _, textView in
                    textView.insertText("1. ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("| --- | --- |"), "Expected table structure to remain intact. got=\(exported)")
                    XCTAssertTrue(exported.contains("1. Alpha"), "Expected ordered shortcut text to stay inside the table cell. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("1. Alpha"), "Table cell ordered shortcut must not convert the row into an ordered list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "table-cell-task-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .tableCell, action: .markerShortcut),
                seedMarkdown: """
                | Name | Value |
                | --- | --- |
                | Alpha | Beta |
                """,
                defaults: [:],
                shortcutVariant: .task,
                prepare: { _, textView in
                    Self.moveCaretToTableCellContentStart(row: 1, col: 0, in: textView)
                },
                perform: { _, textView in
                    textView.insertText("- [ ] ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("| --- | --- |"), "Expected table structure to remain intact. got=\(exported)")
                    XCTAssertTrue(
                        exported.contains("- [ ] Alpha") || exported.contains("- ☐ Alpha"),
                        "Expected table cell to keep literal task shortcut text. got=\(exported)"
                    )
                    XCTAssertFalse(exported.hasPrefix("- [ ]"), "Table cell shortcut must not convert the row into a task list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "table-cell-quote-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .tableCell, action: .markerShortcut),
                seedMarkdown: """
                | Name | Value |
                | --- | --- |
                | Alpha | Beta |
                """,
                defaults: [:],
                shortcutVariant: .quote,
                prepare: { _, textView in
                    Self.moveCaretToTableCellContentStart(row: 1, col: 0, in: textView)
                },
                perform: { _, textView in
                    textView.insertText("> quoted ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("| --- | --- |"), "Expected table structure to remain intact. got=\(exported)")
                    XCTAssertTrue(exported.contains("> quoted Alpha"), "Expected quote shortcut text to stay inside the table cell. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("> quoted"), "Table cell quote shortcut must not convert the row into a blockquote. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "inline-code-ordered-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .inlineCode, action: .markerShortcut),
                seedMarkdown: "`codeValue`\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                shortcutVariant: .ordered,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("codeValue", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                },
                perform: { _, textView in
                    let ns = textView.string as NSString
                    let tokenRange = ns.range(of: "codeValue")
                    XCTAssertNotEqual(tokenRange.location, NSNotFound, "Expected expanded inline-code token")
                    guard tokenRange.location != NSNotFound else { return }
                    textView.insertText("", replacementRange: tokenRange)
                    textView.insertText("1. raw", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("`1. raw`"), "Expected inline code to preserve literal ordered shortcut text. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("1. raw"), "Inline code ordered shortcut must not convert the paragraph into a list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "inline-code-marker-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .inlineCode, action: .markerShortcut),
                seedMarkdown: "`codeValue`\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                shortcutVariant: .bullet,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("codeValue", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                },
                perform: { _, textView in
                    let ns = textView.string as NSString
                    let tokenRange = ns.range(of: "codeValue")
                    XCTAssertNotEqual(tokenRange.location, NSNotFound, "Expected expanded inline-code token")
                    guard tokenRange.location != NSNotFound else { return }
                    textView.insertText("", replacementRange: tokenRange)
                    textView.insertText("- raw", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("`- raw`"), "Expected inline code to preserve literal marker text. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- raw"), "Inline code shortcut must not convert the paragraph into a list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "inline-code-task-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .inlineCode, action: .markerShortcut),
                seedMarkdown: "`codeValue`\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                shortcutVariant: .task,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("codeValue", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                },
                perform: { _, textView in
                    let ns = textView.string as NSString
                    let tokenRange = ns.range(of: "codeValue")
                    XCTAssertNotEqual(tokenRange.location, NSNotFound, "Expected expanded inline-code token")
                    guard tokenRange.location != NSNotFound else { return }
                    textView.insertText("", replacementRange: tokenRange)
                    textView.insertText("- [ ] raw", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("`- [ ] raw`"), "Expected inline code to preserve literal task shortcut text. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- [ ] raw"), "Inline code task shortcut must not convert the paragraph into a task list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "inline-code-quote-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .inlineCode, action: .markerShortcut),
                seedMarkdown: "`codeValue`\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                shortcutVariant: .quote,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("codeValue", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                },
                perform: { _, textView in
                    let ns = textView.string as NSString
                    let tokenRange = ns.range(of: "codeValue")
                    XCTAssertNotEqual(tokenRange.location, NSNotFound, "Expected expanded inline-code token")
                    guard tokenRange.location != NSNotFound else { return }
                    textView.insertText("", replacementRange: tokenRange)
                    textView.insertText("> raw", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("`> raw`"), "Expected inline code to preserve literal quote shortcut text. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("> raw"), "Inline code quote shortcut must not convert the paragraph into a blockquote. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "hybrid-link-destination-ordered-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .linkLiteral, action: .markerShortcut),
                seedMarkdown: "[docs](dest-token)\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                policyProfile: .hybridSyntax,
                shortcutVariant: .ordered,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("docs", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                },
                perform: { _, textView in
                    textView.insertText("1. ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("[docs](1. dest-token)") || exported.contains("[docs](1. dest-token"),
                        "Expected hybrid link destination to keep literal ordered shortcut text. got=\(exported)"
                    )
                    XCTAssertFalse(exported.hasPrefix("1. "), "Hybrid link destination must not convert into an ordered list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "hybrid-link-destination-marker-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .linkLiteral, action: .markerShortcut),
                seedMarkdown: "[docs](dest-token)\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                policyProfile: .hybridSyntax,
                shortcutVariant: .bullet,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("docs", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                },
                perform: { _, textView in
                    textView.insertText("- ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("[docs](- dest-token)") || exported.contains("[docs](- dest-token"),
                        "Expected hybrid link destination to keep literal shortcut text. got=\(exported)"
                    )
                    XCTAssertFalse(exported.hasPrefix("- "), "Hybrid link destination must not convert into a list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "hybrid-link-destination-task-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .linkLiteral, action: .markerShortcut),
                seedMarkdown: "[docs](dest-token)\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                policyProfile: .hybridSyntax,
                shortcutVariant: .task,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("docs", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                },
                perform: { _, textView in
                    textView.insertText("- [ ] ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("[docs]("), "Expected inline link export to remain intact. got=\(exported)")
                    XCTAssertTrue(exported.contains("- [ ] dest-token"), "Expected hybrid link destination to keep literal task shortcut text. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("- [ ] "), "Hybrid link destination task shortcut must not convert into a task list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "hybrid-link-destination-quote-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .linkLiteral, action: .markerShortcut),
                seedMarkdown: "[docs](dest-token)\n\nafter",
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.hybrid.rawValue,
                ],
                policyProfile: .hybridSyntax,
                shortcutVariant: .quote,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("docs", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                },
                perform: { _, textView in
                    textView.insertText("> ", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                    Self.moveCaretToSubstringStart("after", in: textView)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("[docs]("), "Expected inline link export to remain intact. got=\(exported)")
                    XCTAssertTrue(exported.contains("dest-token"), "Expected hybrid link destination to retain the original token. got=\(exported)")
                    XCTAssertTrue(exported.contains("\\>") || exported.contains("> dest-token"), "Expected hybrid link destination to preserve literal quote shortcut text. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("> "), "Hybrid link destination quote shortcut must not convert into a blockquote. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "reference-definition-ordered-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .referenceLiteral, action: .markerShortcut),
                seedMarkdown: """
                [docs]: dest-token

                [docs]
                """,
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.markdown.rawValue,
                ],
                policyProfile: .markdownSyntax,
                shortcutVariant: .ordered,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                },
                perform: { _, textView in
                    textView.insertText("1. ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("[docs]: 1. dest-token"),
                        "Expected reference destination to keep literal ordered shortcut text. got=\(exported)"
                    )
                    XCTAssertFalse(exported.hasPrefix("1. "), "Reference literal ordered shortcut must not convert into a list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "reference-definition-marker-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .referenceLiteral, action: .markerShortcut),
                seedMarkdown: """
                [docs]: dest-token

                [docs]
                """,
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.markdown.rawValue,
                ],
                policyProfile: .markdownSyntax,
                shortcutVariant: .bullet,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                },
                perform: { _, textView in
                    textView.insertText("- ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("[docs]: - dest-token"),
                        "Expected reference destination to keep literal shortcut text. got=\(exported)"
                    )
                    XCTAssertFalse(exported.hasPrefix("- "), "Reference literal shortcut must not convert into a list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "reference-definition-task-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .referenceLiteral, action: .markerShortcut),
                seedMarkdown: """
                [docs]: dest-token

                [docs]
                """,
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.markdown.rawValue,
                ],
                policyProfile: .markdownSyntax,
                shortcutVariant: .task,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                },
                perform: { _, textView in
                    textView.insertText("- [ ] ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported.contains("[docs]: - [ ] dest-token"),
                        "Expected reference destination to keep literal task shortcut text. got=\(exported)"
                    )
                    XCTAssertFalse(exported.hasPrefix("- [ ] "), "Reference literal task shortcut must not convert into a task list. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "reference-definition-quote-shortcut-stays-literal",
                edge: TypingBehaviorEdge(context: .referenceLiteral, action: .markerShortcut),
                seedMarkdown: """
                [docs]: dest-token

                [docs]
                """,
                defaults: [
                    NativeEditorSyntaxVisibilityMode.userDefaultsKey: NativeEditorSyntaxVisibilityMode.markdown.rawValue,
                ],
                policyProfile: .markdownSyntax,
                shortcutVariant: .quote,
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("dest-token", in: textView)
                },
                perform: { _, textView in
                    textView.insertText("> ", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("[docs]:"), "Expected reference definition export to remain intact. got=\(exported)")
                    XCTAssertTrue(exported.contains("dest-token"), "Expected reference definition to retain the original token. got=\(exported)")
                    XCTAssertTrue(exported.contains("> dest-token"), "Expected reference definition to preserve literal quote shortcut text. got=\(exported)")
                    XCTAssertFalse(exported.hasPrefix("> "), "Reference literal quote shortcut must not convert into a blockquote. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "bullet-backspace-unlist",
                edge: TypingBehaviorEdge(context: .bullet, action: .backspaceAtBoundary),
                seedMarkdown: "- alpha\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    _ = vc.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
                },
                assertExport: { exported in
                    XCTAssertEqual(exported, "alpha\n")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-backspace-unlist",
                edge: TypingBehaviorEdge(context: .ordered, action: .backspaceAtBoundary),
                seedMarkdown: "1. alpha\n",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    _ = vc.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
                },
                assertExport: { exported in
                    XCTAssertEqual(exported, "alpha\n")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "ordered-enter-recovers-after-marker-delete",
                edge: TypingBehaviorEdge(context: .ordered, action: .enter),
                seedMarkdown: "1. alpha\n",
                defaults: [:],
                prepare: { _, textView in
                    guard let storage = textView.textStorage else { return }
                    guard let markerIndex = Self.firstMarkerIndex(in: storage, range: NSRange(location: 0, length: storage.length)) else {
                        XCTFail("Expected ordered marker")
                        return
                    }
                    textView.insertText("", replacementRange: NSRange(location: markerIndex, length: 1))
                    textView.setSelectedRange(NSRange(location: markerIndex, length: 0))
                },
                perform: { _, textView in
                    textView.insertNewline(nil)
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                    textView.insertText("next", replacementRange: textView.selectedRange())
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("next"), "Expected newline/typing recovery after marker edit. got=\(exported)")
                }
            )
        )

        out.append(
            TransitionCase(
                id: "task-backspace-unlist-preserve-inline",
                edge: TypingBehaviorEdge(context: .task, action: .backspaceAtBoundary),
                seedMarkdown: "- [ ] **alpha**\n",
                defaults: [
                    "nativeEditor.taskRendering": "gfm",
                ],
                prepare: { _, textView in
                    Self.moveCaretToSubstringStart("alpha", in: textView)
                },
                perform: { vc, textView in
                    _ = vc.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
                    vc.flushPendingExport()
                    let firstPass = NativeMarkdownCodec.exportMarkdown(textView.attributedString(), options: .fromUserDefaults())
                    if firstPass.hasPrefix("- [ ] ") {
                        _ = vc.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:)))
                    }
                },
                assertExport: { exported in
                    XCTAssertTrue(
                        exported == "**alpha**\n" || exported == "- [ ] **alpha**\n",
                        "Expected task backspace boundary to either unlist or remain stable. got=\(exported)"
                    )
                }
            )
        )

        out.append(
            TransitionCase(
                id: "bullet-shift-enter-softbreak",
                edge: TypingBehaviorEdge(context: .bullet, action: .shiftEnter),
                seedMarkdown: "- one",
                defaults: [:],
                prepare: { _, textView in
                    Self.moveCaretToEnd(textView)
                },
                perform: { _, textView in
                    textView.insertLineBreak(nil)
                    textView.insertText("two", replacementRange: textView.selectedRange())
                },
                assertExport: { exported in
                    XCTAssertTrue(exported.contains("- one"), "Expected bullet content retained. got=\(exported)")
                    XCTAssertTrue(exported.contains("two"), "Expected inserted trailing content. got=\(exported)")
                    XCTAssertFalse(exported.contains("- two"), "Shift+Enter should not create another bullet marker. got=\(exported)")
                }
            )
        )

        return out
    }

    // MARK: - Helpers

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
    private static func moveCaretToEnd(_ textView: NativeMarkdownTextView) {
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    }

    @MainActor
    private static func moveCaretToSubstringStart(_ needle: String, in textView: NativeMarkdownTextView) {
        let ns = textView.string as NSString
        let range = ns.range(of: needle)
        XCTAssertNotEqual(range.location, NSNotFound, "Expected substring '\(needle)'")
        guard range.location != NSNotFound else { return }
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
    }

    @MainActor
    private static func moveCaretToSubstringEnd(_ needle: String, in textView: NativeMarkdownTextView) {
        let ns = textView.string as NSString
        let range = ns.range(of: needle)
        XCTAssertNotEqual(range.location, NSNotFound, "Expected substring '\(needle)'")
        guard range.location != NSNotFound else { return }
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

    private static func firstCheckboxIndex(in storage: NSTextStorage, range: NSRange) -> Int? {
        var out: Int?
        storage.enumerateAttribute(.kernCheckbox, in: range, options: []) { value, r, stop in
            if (value as? Bool) == true {
                out = r.location
                stop.pointee = true
            }
        }
        return out
    }

    private static func firstMarkerIndex(in storage: NSTextStorage, range: NSRange) -> Int? {
        var out: Int?
        storage.enumerateAttribute(.kernMarker, in: range, options: []) { value, r, stop in
            if (value as? Bool) == true {
                out = r.location
                stop.pointee = true
            }
        }
        return out
    }

    @MainActor
    private func drainMainRunLoop() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    private func attachReport(_ content: String, name: String) {
        let attachment = XCTAttachment(string: content)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
