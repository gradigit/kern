import Foundation

enum TypingBehaviorContextClass: String, CaseIterable, Sendable {
    case paragraph
    case bullet
    case ordered
    case task
    case orderedTask
    case nestedBullet
    case nestedOrdered
    case nestedTask
    case nestedOrderedTask
    case headingTask
    case quote
    case codeFence
    case tableCell
    case inlineCode
    case linkLiteral
    case referenceLiteral
}

enum TypingBehaviorAction: String, CaseIterable, Sendable {
    case markerShortcut
    case enter
    case secondEnterExit
    case shiftEnter
    case tabIndent
    case shiftTabOutdent
    case backspaceAtBoundary
    case spaceToggle
}

enum TypingBehaviorMarkerState: String, CaseIterable, Sendable {
    case none
    case bullet
    case ordered
    case task
    case orderedTask
    case quote
    case codeFence
    case tableCell
    case inlineCode
    case linkLiteral
    case referenceLiteral

    static func `default`(for context: TypingBehaviorContextClass) -> TypingBehaviorMarkerState {
        switch context {
        case .paragraph:
            return .none
        case .bullet, .nestedBullet:
            return .bullet
        case .ordered, .nestedOrdered:
            return .ordered
        case .task, .nestedTask, .headingTask:
            return .task
        case .orderedTask, .nestedOrderedTask:
            return .orderedTask
        case .quote:
            return .quote
        case .codeFence:
            return .codeFence
        case .tableCell:
            return .tableCell
        case .inlineCode:
            return .inlineCode
        case .linkLiteral:
            return .linkLiteral
        case .referenceLiteral:
            return .referenceLiteral
        }
    }
}

enum TypingBehaviorIndentBucket: String, CaseIterable, Sendable {
    case root
    case nested

    static func `default`(for context: TypingBehaviorContextClass) -> TypingBehaviorIndentBucket {
        switch context {
        case .nestedBullet, .nestedOrdered, .nestedTask, .nestedOrderedTask:
            return .nested
        default:
            return .root
        }
    }
}

enum TypingBehaviorContentState: String, CaseIterable, Sendable {
    case empty
    case nonEmpty
}

enum TypingBehaviorPolicyProfile: String, CaseIterable, Sendable {
    case defaultWysiwyg
    case orderedTasks
    case hybridSyntax
    case markdownSyntax

    static func `default`(for context: TypingBehaviorContextClass) -> TypingBehaviorPolicyProfile {
        switch context {
        case .orderedTask, .nestedOrderedTask:
            return .orderedTasks
        case .inlineCode:
            return .hybridSyntax
        case .referenceLiteral:
            return .markdownSyntax
        default:
            return .defaultWysiwyg
        }
    }
}

enum TypingBehaviorShortcutVariant: String, CaseIterable, Sendable {
    case none
    case bullet
    case ordered
    case task
    case quote

    static func `default`(for action: TypingBehaviorAction) -> TypingBehaviorShortcutVariant {
        switch action {
        case .markerShortcut:
            return .bullet
        default:
            return .none
        }
    }
}

struct TypingBehaviorEdge: Hashable, Sendable {
    let context: TypingBehaviorContextClass
    let action: TypingBehaviorAction
}

struct TypingBehaviorFactors: Hashable, Sendable {
    let context: TypingBehaviorContextClass
    let action: TypingBehaviorAction
    let markerState: TypingBehaviorMarkerState
    let indentBucket: TypingBehaviorIndentBucket
    let contentState: TypingBehaviorContentState
    let policyProfile: TypingBehaviorPolicyProfile
    let shortcutVariant: TypingBehaviorShortcutVariant

    var edge: TypingBehaviorEdge {
        TypingBehaviorEdge(context: context, action: action)
    }

    var label: String {
        [
            context.rawValue,
            action.rawValue,
            markerState.rawValue,
            indentBucket.rawValue,
            contentState.rawValue,
            policyProfile.rawValue,
            shortcutVariant.rawValue,
        ].joined(separator: ":")
    }
}

enum TypingBehaviorCoverageLane: String, Sendable {
    case pr
    case nightly

    static func current() -> TypingBehaviorCoverageLane {
        if let raw = TestRuntimeConfig.string("KERN_TYPING_COVERAGE_LANE"),
           let lane = TypingBehaviorCoverageLane(rawValue: raw) {
            return lane
        }
        if let seeds = TestRuntimeConfig.int("KERN_TYPING_STATEFUL_SEEDS", default: 24), seeds >= 120 {
            return .nightly
        }
        return .pr
    }

    var pairwiseThreshold: Double { 0.95 }
    var criticalTripleThreshold: Double? {
        switch self {
        case .pr:
            return nil
        case .nightly:
            return 0.90
        }
    }
}

enum TypingBehaviorCoverageDimension: String, CaseIterable, Sendable {
    case context
    case action
    case markerState
    case indentBucket
    case contentState
    case policyProfile
    case shortcutVariant
}

struct TypingBehaviorValueRef: Hashable, Sendable {
    let dimension: TypingBehaviorCoverageDimension
    let value: String
}

struct TypingBehaviorPairKey: Hashable, Sendable {
    let first: TypingBehaviorValueRef
    let second: TypingBehaviorValueRef

    init(_ lhs: TypingBehaviorValueRef, _ rhs: TypingBehaviorValueRef) {
        if lhs.dimension.rawValue < rhs.dimension.rawValue {
            first = lhs
            second = rhs
        } else {
            first = rhs
            second = lhs
        }
    }
}

struct TypingBehaviorTripleKey: Hashable, Sendable {
    let values: [TypingBehaviorValueRef]

    init(_ refs: [TypingBehaviorValueRef]) {
        values = refs.sorted { lhs, rhs in
            lhs.dimension.rawValue < rhs.dimension.rawValue
        }
    }
}

struct TypingBehaviorCoverageContract {
    let lane: TypingBehaviorCoverageLane
    let requiredFactors: Set<TypingBehaviorFactors>

    static func current() -> TypingBehaviorCoverageContract {
        let lane = TypingBehaviorCoverageLane.current()
        return TypingBehaviorCoverageContract(lane: lane, requiredFactors: Set(requiredFactorCatalog()))
    }

    var requiredEdges: Set<TypingBehaviorEdge> {
        Set(requiredFactors.map(\.edge))
    }

    var requiredPairwise: Set<TypingBehaviorPairKey> {
        Set(requiredFactors.flatMap(Self.pairKeys(for:)))
    }

    var requiredCriticalTriples: Set<TypingBehaviorTripleKey> {
        Set(requiredFactors.flatMap(Self.criticalTripleKeys(for:)))
    }

    fileprivate static func pairKeys(for factors: TypingBehaviorFactors) -> [TypingBehaviorPairKey] {
        let refs = valueRefs(for: factors)
        var out: [TypingBehaviorPairKey] = []
        for first in 0..<refs.count {
            for second in (first + 1)..<refs.count {
                out.append(TypingBehaviorPairKey(refs[first], refs[second]))
            }
        }
        return out
    }

    fileprivate static func criticalTripleKeys(for factors: TypingBehaviorFactors) -> [TypingBehaviorTripleKey] {
        let refs = valueRefs(for: factors)
        var out: [TypingBehaviorTripleKey] = []
        for first in 0..<refs.count {
            for second in (first + 1)..<refs.count {
                for third in (second + 1)..<refs.count {
                    out.append(TypingBehaviorTripleKey([refs[first], refs[second], refs[third]]))
                }
            }
        }
        return out
    }

    private static func valueRefs(for factors: TypingBehaviorFactors) -> [TypingBehaviorValueRef] {
        [
            .init(dimension: .context, value: factors.context.rawValue),
            .init(dimension: .action, value: factors.action.rawValue),
            .init(dimension: .markerState, value: factors.markerState.rawValue),
            .init(dimension: .indentBucket, value: factors.indentBucket.rawValue),
            .init(dimension: .contentState, value: factors.contentState.rawValue),
            .init(dimension: .policyProfile, value: factors.policyProfile.rawValue),
            .init(dimension: .shortcutVariant, value: factors.shortcutVariant.rawValue),
        ]
    }

    private static func make(
        context: TypingBehaviorContextClass,
        action: TypingBehaviorAction,
        markerState: TypingBehaviorMarkerState? = nil,
        indentBucket: TypingBehaviorIndentBucket? = nil,
        contentState: TypingBehaviorContentState = .nonEmpty,
        policyProfile: TypingBehaviorPolicyProfile? = nil,
        shortcutVariant: TypingBehaviorShortcutVariant? = nil
    ) -> TypingBehaviorFactors {
        TypingBehaviorFactors(
            context: context,
            action: action,
            markerState: markerState ?? .default(for: context),
            indentBucket: indentBucket ?? .default(for: context),
            contentState: contentState,
            policyProfile: policyProfile ?? .default(for: context),
            shortcutVariant: shortcutVariant ?? .default(for: action)
        )
    }

    private static func requiredFactorCatalog() -> [TypingBehaviorFactors] {
        [
            make(context: .paragraph, action: .markerShortcut, contentState: .empty, shortcutVariant: .bullet),
            make(context: .paragraph, action: .markerShortcut, contentState: .empty, shortcutVariant: .ordered),
            make(context: .paragraph, action: .markerShortcut, contentState: .empty, shortcutVariant: .task),
            make(context: .paragraph, action: .markerShortcut, contentState: .empty, shortcutVariant: .quote),

            make(context: .bullet, action: .enter),
            make(context: .bullet, action: .secondEnterExit),
            make(context: .bullet, action: .shiftEnter),
            make(context: .bullet, action: .tabIndent),
            make(context: .bullet, action: .shiftTabOutdent, indentBucket: .nested),
            make(context: .bullet, action: .backspaceAtBoundary),

            make(context: .ordered, action: .enter),
            make(context: .ordered, action: .secondEnterExit),
            make(context: .ordered, action: .tabIndent),
            make(context: .ordered, action: .shiftTabOutdent, indentBucket: .nested),
            make(context: .ordered, action: .backspaceAtBoundary),
            make(context: .ordered, action: .markerShortcut, shortcutVariant: .bullet),

            make(context: .task, action: .enter),
            make(context: .task, action: .secondEnterExit),
            make(context: .task, action: .tabIndent),
            make(context: .task, action: .shiftTabOutdent, indentBucket: .nested),
            make(context: .task, action: .backspaceAtBoundary),
            make(context: .task, action: .spaceToggle),

            make(context: .orderedTask, action: .enter, policyProfile: .orderedTasks),
            make(context: .orderedTask, action: .secondEnterExit, policyProfile: .orderedTasks),
            make(context: .orderedTask, action: .tabIndent, policyProfile: .orderedTasks),
            make(context: .orderedTask, action: .shiftTabOutdent, indentBucket: .nested, policyProfile: .orderedTasks),
            make(context: .orderedTask, action: .spaceToggle, policyProfile: .orderedTasks),

            make(context: .nestedBullet, action: .shiftTabOutdent),
            make(context: .nestedBullet, action: .backspaceAtBoundary),

            make(context: .nestedOrdered, action: .enter),
            make(context: .nestedOrdered, action: .shiftTabOutdent),
            make(context: .nestedOrdered, action: .backspaceAtBoundary),
            make(context: .nestedOrdered, action: .markerShortcut, shortcutVariant: .task),

            make(context: .nestedTask, action: .tabIndent),
            make(context: .nestedTask, action: .shiftTabOutdent),
            make(context: .nestedTask, action: .backspaceAtBoundary),
            make(context: .nestedTask, action: .markerShortcut, shortcutVariant: .ordered),

            make(context: .nestedOrderedTask, action: .enter, policyProfile: .orderedTasks),
            make(context: .nestedOrderedTask, action: .tabIndent, policyProfile: .orderedTasks),

            make(context: .headingTask, action: .enter),
            make(context: .quote, action: .enter),
            make(context: .quote, action: .secondEnterExit),
            make(context: .codeFence, action: .markerShortcut, shortcutVariant: .bullet),
            make(context: .codeFence, action: .markerShortcut, shortcutVariant: .ordered),
            make(context: .codeFence, action: .markerShortcut, shortcutVariant: .task),
            make(context: .codeFence, action: .markerShortcut, shortcutVariant: .quote),
            make(context: .tableCell, action: .markerShortcut, shortcutVariant: .bullet),
            make(context: .tableCell, action: .markerShortcut, shortcutVariant: .ordered),
            make(context: .tableCell, action: .markerShortcut, shortcutVariant: .task),
            make(context: .tableCell, action: .markerShortcut, shortcutVariant: .quote),
            make(context: .inlineCode, action: .markerShortcut, policyProfile: .hybridSyntax, shortcutVariant: .bullet),
            make(context: .inlineCode, action: .markerShortcut, policyProfile: .hybridSyntax, shortcutVariant: .ordered),
            make(context: .inlineCode, action: .markerShortcut, policyProfile: .hybridSyntax, shortcutVariant: .task),
            make(context: .inlineCode, action: .markerShortcut, policyProfile: .hybridSyntax, shortcutVariant: .quote),
            make(context: .linkLiteral, action: .markerShortcut, policyProfile: .hybridSyntax, shortcutVariant: .bullet),
            make(context: .linkLiteral, action: .markerShortcut, policyProfile: .hybridSyntax, shortcutVariant: .ordered),
            make(context: .linkLiteral, action: .markerShortcut, policyProfile: .hybridSyntax, shortcutVariant: .task),
            make(context: .linkLiteral, action: .markerShortcut, policyProfile: .hybridSyntax, shortcutVariant: .quote),
            make(context: .referenceLiteral, action: .markerShortcut, policyProfile: .markdownSyntax, shortcutVariant: .bullet),
            make(context: .referenceLiteral, action: .markerShortcut, policyProfile: .markdownSyntax, shortcutVariant: .ordered),
            make(context: .referenceLiteral, action: .markerShortcut, policyProfile: .markdownSyntax, shortcutVariant: .task),
            make(context: .referenceLiteral, action: .markerShortcut, policyProfile: .markdownSyntax, shortcutVariant: .quote),
        ]
    }
}

struct TypingBehaviorCoverage {
    private(set) var contract: TypingBehaviorCoverageContract
    private(set) var observedFactors: Set<TypingBehaviorFactors> = []
    private(set) var observedCaseIDs: [String] = []

    init(contract: TypingBehaviorCoverageContract) {
        self.contract = contract
    }

    mutating func record(factors: TypingBehaviorFactors, caseID: String) {
        observedFactors.insert(factors)
        observedCaseIDs.append(caseID)
    }

    var observedEdges: Set<TypingBehaviorEdge> {
        Set(observedFactors.map(\.edge))
    }

    var coveredRequiredCount: Int {
        observedFactors.intersection(contract.requiredFactors).count
    }

    var totalRequiredCount: Int {
        contract.requiredFactors.count
    }

    var requiredCoverageRatio: Double {
        guard !contract.requiredFactors.isEmpty else { return 1.0 }
        return Double(coveredRequiredCount) / Double(contract.requiredFactors.count)
    }

    var missingRequiredFactors: [TypingBehaviorFactors] {
        contract.requiredFactors.subtracting(observedFactors).sorted { lhs, rhs in
            lhs.label < rhs.label
        }
    }

    var missingRequiredEdges: [TypingBehaviorEdge] {
        contract.requiredEdges.subtracting(observedEdges).sorted {
            if $0.context.rawValue == $1.context.rawValue {
                return $0.action.rawValue < $1.action.rawValue
            }
            return $0.context.rawValue < $1.context.rawValue
        }
    }

    var pairwiseCoverageRatio: Double {
        let required = contract.requiredPairwise
        guard !required.isEmpty else { return 1.0 }
        return Double(required.intersection(observedPairwise).count) / Double(required.count)
    }

    var criticalTripleCoverageRatio: Double {
        let required = contract.requiredCriticalTriples
        guard !required.isEmpty else { return 1.0 }
        return Double(required.intersection(observedCriticalTriples).count) / Double(required.count)
    }

    var observedPairwise: Set<TypingBehaviorPairKey> {
        Set(observedFactors.flatMap { contractKeyPairs(for: $0) })
    }

    var observedCriticalTriples: Set<TypingBehaviorTripleKey> {
        Set(observedFactors.flatMap { contractKeyTriples(for: $0) })
    }

    func renderReport() -> String {
        var lines: [String] = []
        lines.append("typing_behavior_matrix_coverage")
        lines.append("lane=\(contract.lane.rawValue)")
        lines.append("required_factor_cases=\(totalRequiredCount)")
        lines.append("covered_required_factor_cases=\(coveredRequiredCount)")
        lines.append(String(format: "required_factor_coverage_ratio=%.4f", requiredCoverageRatio))
        lines.append("required_edges=\(contract.requiredEdges.count)")
        lines.append("covered_required_edges=\(observedEdges.intersection(contract.requiredEdges).count)")
        lines.append(String(format: "pairwise_coverage_ratio=%.4f", pairwiseCoverageRatio))
        lines.append("required_pairwise=\(contract.requiredPairwise.count)")
        lines.append("covered_pairwise=\(contract.requiredPairwise.intersection(observedPairwise).count)")
        lines.append(String(format: "critical_triple_coverage_ratio=%.4f", criticalTripleCoverageRatio))
        lines.append("required_critical_triples=\(contract.requiredCriticalTriples.count)")
        lines.append("covered_critical_triples=\(contract.requiredCriticalTriples.intersection(observedCriticalTriples).count)")
        lines.append("observed_cases=\(observedCaseIDs.count)")
        if missingRequiredFactors.isEmpty {
            lines.append("missing_required_factor_cases=none")
        } else {
            lines.append(
                "missing_required_factor_cases=\(missingRequiredFactors.map(\.label).joined(separator: ","))"
            )
        }
        if missingRequiredEdges.isEmpty {
            lines.append("missing_required_edges=none")
        } else {
            let missing = missingRequiredEdges
                .map { "\($0.context.rawValue):\($0.action.rawValue)" }
                .joined(separator: ",")
            lines.append("missing_required_edges=\(missing)")
        }
        return lines.joined(separator: "\n")
    }

    private func contractKeyPairs(for factors: TypingBehaviorFactors) -> [TypingBehaviorPairKey] {
        TypingBehaviorCoverageContract
            .pairKeys(for: factors)
    }

    private func contractKeyTriples(for factors: TypingBehaviorFactors) -> [TypingBehaviorTripleKey] {
        TypingBehaviorCoverageContract
            .criticalTripleKeys(for: factors)
    }
}
