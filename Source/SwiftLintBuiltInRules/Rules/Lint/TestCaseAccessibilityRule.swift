import Foundation
import SwiftSyntax

struct TestCaseAccessibilityRule: SwiftSyntaxRule, OptInRule,
                                         ConfigurationProviderRule, SubstitutionCorrectableRule {
    var configuration = TestCaseAccessibilityConfiguration()

    static let description = RuleDescription(
        identifier: "test_case_accessibility",
        name: "Test Case Accessibility",
        description: "Test cases should only contain private non-test members",
        kind: .lint,
        nonTriggeringExamples: TestCaseAccessibilityRuleExamples.nonTriggeringExamples,
        triggeringExamples: TestCaseAccessibilityRuleExamples.triggeringExamples,
        corrections: TestCaseAccessibilityRuleExamples.corrections
    )

    func makeVisitor(file: SwiftLintFile) -> ViolationsSyntaxVisitor {
        Visitor(allowedPrefixes: configuration.allowedPrefixes, testParentClasses: configuration.testParentClasses)
    }

    func violationRanges(in file: SwiftLintFile) -> [NSRange] {
        makeVisitor(file: file)
            .walk(tree: file.syntaxTree, handler: \.violations)
            .compactMap {
                file.stringView.NSRange(start: $0.position, end: $0.position)
            }
    }

    func substitution(for violationRange: NSRange, in file: SwiftLintFile) -> (NSRange, String)? {
        (violationRange, "private ")
    }
}

private extension TestCaseAccessibilityRule {
    final class Visitor: ViolationsSyntaxVisitor {
        private let allowedPrefixes: Set<String>
        private let testParentClasses: Set<String>

        init(allowedPrefixes: Set<String>, testParentClasses: Set<String>) {
            self.allowedPrefixes = allowedPrefixes
            self.testParentClasses = testParentClasses
            super.init(viewMode: .sourceAccurate)
        }

        override var skippableDeclarations: [DeclSyntaxProtocol.Type] { .all }

        override func visitPost(_ node: ClassDeclSyntax) {
            guard !testParentClasses.isDisjoint(with: node.inheritedTypes) else {
                return
            }

            violations.append(
                contentsOf: XCTestClassVisitor(allowedPrefixes: allowedPrefixes)
                    .walk(tree: node.memberBlock, handler: \.violations)
            )
        }
    }

    final class XCTestClassVisitor: ViolationsSyntaxVisitor {
        private let allowedPrefixes: Set<String>

        init(allowedPrefixes: Set<String>) {
            self.allowedPrefixes = allowedPrefixes
            super.init(viewMode: .sourceAccurate)
        }

        override var skippableDeclarations: [DeclSyntaxProtocol.Type] { .all }

        override func visitPost(_ node: VariableDeclSyntax) {
            guard !node.modifiers.containsPrivateOrFileprivate(),
                  !XCTestHelpers.isXCTestVariable(node) else {
                return
            }

            for binding in node.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      case let name = pattern.identifier.text,
                      !allowedPrefixes.contains(where: name.hasPrefix) else {
                    continue
                }

                violations.append(node.bindingSpecifier.positionAfterSkippingLeadingTrivia)
                return
            }
        }

        override func visitPost(_ node: FunctionDeclSyntax) {
            guard hasViolation(modifiers: node.modifiers, identifierToken: node.name),
                  !XCTestHelpers.isXCTestFunction(node) else {
                return
            }

            violations.append(node.positionAfterSkippingLeadingTrivia)
        }

        override func visitPost(_ node: ClassDeclSyntax) {
            if hasViolation(modifiers: node.modifiers, identifierToken: node.name) {
                violations.append(node.classKeyword.positionAfterSkippingLeadingTrivia)
            }
        }

        override func visitPost(_ node: EnumDeclSyntax) {
            if hasViolation(modifiers: node.modifiers, identifierToken: node.name) {
                violations.append(node.enumKeyword.positionAfterSkippingLeadingTrivia)
            }
        }

        override func visitPost(_ node: StructDeclSyntax) {
            if hasViolation(modifiers: node.modifiers, identifierToken: node.name) {
                violations.append(node.structKeyword.positionAfterSkippingLeadingTrivia)
            }
        }

        override func visitPost(_ node: ActorDeclSyntax) {
            if hasViolation(modifiers: node.modifiers, identifierToken: node.name) {
                violations.append(node.actorKeyword.positionAfterSkippingLeadingTrivia)
            }
        }

        override func visitPost(_ node: TypeAliasDeclSyntax) {
            if hasViolation(modifiers: node.modifiers, identifierToken: node.name) {
                violations.append(node.typealiasKeyword.positionAfterSkippingLeadingTrivia)
            }
        }

        private func hasViolation(modifiers: DeclModifierListSyntax, identifierToken: TokenSyntax) -> Bool {
               !modifiers.containsPrivateOrFileprivate()
            && !allowedPrefixes.contains(where: identifierToken.text.hasPrefix)
        }
    }
}

private extension ClassDeclSyntax {
    var inheritedTypes: [String] {
        inheritanceClause?.inheritedTypes.compactMap { type in
            type.type.as(IdentifierTypeSyntax.self)?.name.text
        } ?? []
    }
}

private enum XCTestHelpers {
    private static let testVariableNames: Set = [
        "allTests"
    ]

    static func isXCTestFunction(_ function: FunctionDeclSyntax) -> Bool {
        guard !function.modifiers.contains(keyword: .override) else {
            return true
        }

        return !function.modifiers.containsStaticOrClass &&
        function.name.text.hasPrefix("test") &&
        function.signature.parameterClause.parameters.isEmpty
    }

    static func isXCTestVariable(_ variable: VariableDeclSyntax) -> Bool {
        guard !variable.modifiers.contains(keyword: .override) else {
            return true
        }

        return
            variable.modifiers.containsStaticOrClass &&
            variable.bindings
                .compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text }
                .allSatisfy(testVariableNames.contains)
    }
}
