//
//  MockServiceMacros.swift
//  MockServiceMacroPlugin
//
//  Implements the @MockService (member macro) and @MockMethod (body macro).
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import Foundation

// MARK: - Plugin Entry Point

@main
struct MockServiceMacroPluginEntry: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MockServiceMacro.self,
        MockMethodMacro.self,
    ]
}

// MARK: - @MockService — Member Macro

/// Injects `sequencer` property and `init(configuration:sharedState:)` into a mock actor.
///
/// Scans the actor's existing members for `CurrentValueSubject` properties and
/// generates initializer code that:
/// 1. Creates the `MockCallSequencer` with shared state support.
/// 2. For each `CurrentValueSubject` property, checks if a shared state binding exists
///    (via `configuration.bindings`), then falls back to `configuration.initialState`,
///    and finally defaults to `.idle`.
///
/// Shared state bindings work with int-based raw values (e.g. `ServiceStatus(rawValue: 3)`).
public struct MockServiceMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        // Ensure attached to an actor.
        guard let actorDecl = declaration.as(ActorDeclSyntax.self) else {
            throw MacroError("@MockService can only be applied to an actor declaration.")
        }

        // Detect access level.
        let isPublic = actorDecl.modifiers.contains { $0.name.text == "public" }
        let access = isPublic ? "public " : ""

        // Scan existing members for CurrentValueSubject properties.
        let subjectProperties = findCurrentValueSubjectProperties(in: actorDecl)

        // Generate the sequencer property.
        var members: [DeclSyntax] = []
        members.append(DeclSyntax(stringLiteral: "private let sequencer: MockCallSequencer"))

        // Generate init(configuration:sharedState:).
        var initLines: [String] = []
        initLines.append("    \(access)init(configuration: MockServiceEntry, sharedState: MockSharedState? = nil) {")
        initLines.append("        self.sequencer = MockCallSequencer(entry: configuration, sharedState: sharedState)")

        for prop in subjectProperties {
            let name = prop.name
            let fullType = prop.fullTypeString
            let valueType = prop.valueType

            // Priority: binding → initialState → default
            initLines.append("        if let bindingKey = configuration.bindings?[\"\(name)\"],")
            initLines.append("           let subject = sharedState?.subject(for: bindingKey) {")
            initLines.append("            if case .int(let rawValue) = subject.value,")
            initLines.append("               let status = \(valueType)(rawValue: rawValue) {")
            initLines.append("                self.\(name) = \(fullType)(status)")
            initLines.append("            } else {")
            initLines.append("                self.\(name) = \(fullType)(.idle)")
            initLines.append("            }")
            initLines.append("        } else if let initialState = configuration.initialState,")
            initLines.append("                  let stateValue = initialState[\"\(name)\"],")
            initLines.append("                  case .int(let rawValue) = stateValue,")
            initLines.append("                  let status = \(valueType)(rawValue: rawValue) {")
            initLines.append("            self.\(name) = \(fullType)(status)")
            initLines.append("        } else {")
            initLines.append("            self.\(name) = \(fullType)(.idle)")
            initLines.append("        }")
        }

        initLines.append("    }")

        members.append(DeclSyntax(stringLiteral: initLines.joined(separator: "\n")))

        return members
    }
}

// MARK: - CurrentValueSubject Detection

extension MockServiceMacro {

    struct SubjectProperty {
        let name: String
        let fullTypeString: String  // e.g. "CurrentValueSubject<ServiceStatus, Never>"
        let valueType: String       // e.g. "ServiceStatus"
    }

    static func findCurrentValueSubjectProperties(in actorDecl: ActorDeclSyntax) -> [SubjectProperty] {
        var results: [SubjectProperty] = []

        for member in actorDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation else {
                continue
            }

            let typeString = typeAnnotation.type.trimmedDescription
            guard typeString.hasPrefix("CurrentValueSubject") else { continue }

            let name = pattern.identifier.text
            let valueType = extractValueType(from: typeString)
            results.append(SubjectProperty(
                name: name,
                fullTypeString: typeString,
                valueType: valueType
            ))
        }

        return results
    }

    /// Extracts the first generic parameter from "CurrentValueSubject<Foo, Bar>" → "Foo"
    static func extractValueType(from typeString: String) -> String {
        guard let openAngle = typeString.firstIndex(of: "<"),
              let closeAngle = typeString.lastIndex(of: ">") else {
            return "Any"
        }
        let inner = typeString[typeString.index(after: openAngle)..<closeAngle]
        let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.first ?? "Any"
    }
}

// MARK: - @MockMethod — Body Macro

/// Generates the body of a mock function that delegates to `MockCallSequencer`.
///
/// Reads the function name and return type from the declaration syntax.
/// Optionally accepts a custom method key string for overloaded methods.
public struct MockMethodMacro: BodyMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {

        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            throw MacroError("@MockMethod can only be applied to a function declaration.")
        }

        let functionName = funcDecl.name.text

        // Check if a custom method key was provided: @MockMethod("customKey")
        let methodKey = extractMethodKey(from: node) ?? functionName

        // Determine return type and throwing behavior.
        let returnType = funcDecl.signature.returnClause?.type.trimmedDescription
        let isThrowing = funcDecl.signature.effectSpecifiers?.throwsClause != nil

        // Generate the appropriate body statement.
        let bodyStatement: String

        if let returnType = returnType {
            // Method returns a value — use nextDecodedValue.
            if isThrowing {
                bodyStatement = "try await sequencer.nextDecodedValue(for: \"\(methodKey)\", as: \(returnType).self)"
            } else {
                bodyStatement = "try! await sequencer.nextDecodedValue(for: \"\(methodKey)\", as: \(returnType).self)"
            }
        } else {
            // Void method — use recordVoidCall.
            if isThrowing {
                bodyStatement = "try await sequencer.recordVoidCall(for: \"\(methodKey)\")"
            } else {
                bodyStatement = "try? await sequencer.recordVoidCall(for: \"\(methodKey)\")"
            }
        }

        let codeBlock = CodeBlockItemSyntax(
            item: .expr(ExprSyntax(stringLiteral: bodyStatement))
        )
        return [codeBlock]
    }

    /// Extracts the custom method key from @MockMethod("someKey"), if provided.
    private static func extractMethodKey(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
              let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        let text = segment.content.text
        return text.isEmpty ? nil : text
    }
}

// MARK: - MacroError

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}
