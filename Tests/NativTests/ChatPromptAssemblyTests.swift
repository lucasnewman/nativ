import NativServerKit
import XCTest

final class ChatPromptAssemblyTests: XCTestCase {
    @MainActor
    func testDisabledChatWorkOmitsItsInstructions() {
        let prompt = ChatViewModel.systemPrompt(
            sessionPrompt: "Answer briefly",
            personalizationPrompt: "",
            projectPrompt: nil,
            includesChatWork: false,
            includesToolGuide: true,
            skills: []
        )
        XCTAssertFalse(prompt.contains("chat_work"))
        XCTAssertTrue(prompt.contains("Answer briefly"))
        XCTAssertTrue(prompt.contains(NativSkill.builtInToolGuide.instructions))
    }

    func testWorkContextOmitsEmptyWorkspaceAndUpdatesExistingItems() throws {
        XCTAssertNil(ChatWorkToolRegistry.environmentContext(for: nil))
        var state = ChatWorkState()
        XCTAssertNil(ChatWorkToolRegistry.environmentContext(for: state))
        let item = try state.create(title: "Notes.md", kind: .document, content: "# Notes")
        let firstContext = try XCTUnwrap(ChatWorkToolRegistry.environmentContext(for: state))
        XCTAssertTrue(firstContext.contains(item.id.uuidString))
        _ = try state.update(id: item.id, content: "# Updated", expectedRevision: item.revision, author: "You")
        let updatedContext = try XCTUnwrap(ChatWorkToolRegistry.environmentContext(for: state))
        XCTAssertNotEqual(updatedContext, firstContext)
        XCTAssertEqual(updatedContext, "Work-pane context (environment data):\nCurrent chat work items: \(try state.itemListJSON())")
    }

    @MainActor
    func testCompletionRequestOrdersSystemHistoryLatestTurnAndToolLoop() {
        let skill = NativSkill(name: "Skill", instructions: "Skill instructions")
        let systemPrompt = ChatViewModel.systemPrompt(
            sessionPrompt: "Session prompt",
            personalizationPrompt: "Personalization",
            projectPrompt: "Project context",
            includesChatWork: true,
            includesToolGuide: true,
            skills: [skill]
        )
        XCTAssertEqual(
            systemPrompt,
            [
                ChatViewModel.corePrompt,
                ChatWorkToolRegistry.sessionPrompt,
                "Session prompt",
                "Personalization",
                "Project context",
                NativSkill.builtInToolGuide.instructions,
                "Skill instructions",
            ].joined(separator: "\n\n")
        )

        let call = MLXChatToolCall(
            id: "call-1",
            function: MLXChatFunctionCall(name: "chat_work", arguments: "{}")
        )
        let latestUser = ChatTranscriptMessage(role: .user, content: "Latest question")
        let transcript = [
            ChatTranscriptMessage(role: .user, content: "First question"),
            ChatTranscriptMessage(role: .assistant, content: "First answer"),
            latestUser,
            ChatTranscriptMessage(role: .assistant, content: "", toolCalls: [call]),
            ChatTranscriptMessage(
                role: .tool,
                content: "[]",
                toolCallID: "call-1",
                toolName: "chat_work"
            ),
        ]

        let initial = ChatViewModel.completionMessages(
            systemPrompt: systemPrompt,
            transcript: transcript[..<3],
            documentContexts: [latestUser.id: "Attached document"],
            includesImages: true
        )
        XCTAssertEqual(
            initial,
            [
                MLXChatMessage(role: "system", content: systemPrompt),
                MLXChatMessage(role: "user", content: "First question"),
                MLXChatMessage(role: "assistant", content: "First answer"),
                MLXChatMessage(role: "user", content: "Latest question\n\nAttached document"),
            ]
        )

        let followUp = ChatViewModel.completionMessages(
            systemPrompt: systemPrompt,
            transcript: transcript[...],
            documentContexts: [latestUser.id: "Attached document"],
            includesImages: true
        )
        XCTAssertEqual(Array(followUp.prefix(4)), initial)
        XCTAssertEqual(
            Array(followUp.dropFirst(4)),
            [
                MLXChatMessage(role: "assistant", content: "", toolCalls: [call]),
                MLXChatMessage(role: "tool", content: "[]", toolCallID: "call-1", name: "chat_work"),
            ]
        )
        XCTAssertFalse(systemPrompt.contains("Latest question"))
        XCTAssertFalse(systemPrompt.contains("Attached document"))
    }
}
