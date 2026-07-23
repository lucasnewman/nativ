import XCTest

final class NativSettingsTests: XCTestCase {
    func testLaunchArgumentsRouteEachPreloadedModelToItsOwnFlag() {
        let settings = NativSettings(
            languageModelID: "org/language",
            imageGenerationModelID: "org/image",
            textToSpeechModelID: "org/tts",
            speechToTextModelID: "org/stt"
        )

        XCTAssertEqual(
            Array(settings.launchArguments.prefix(10)),
            [
                "--port", "8080",
                "--max-tokens", "2048",
                "--model", "org/language",
                "--image-model", "org/image",
                "--tts-model", "org/tts",
            ]
        )
        XCTAssertTrue(
            settings.launchArguments.containsAdjacent(
                "--stt-model",
                "org/stt"
            )
        )
    }

    func testEmptyPreloadSelectionsAreOmitted() {
        let settings = NativSettings(
            languageModelID: " ",
            imageGenerationModelID: "",
            textToSpeechModelID: "\n",
            speechToTextModelID: nil
        )

        XCTAssertFalse(settings.launchArguments.contains("--model"))
        XCTAssertFalse(settings.launchArguments.contains("--image-model"))
        XCTAssertFalse(settings.launchArguments.contains("--tts-model"))
        XCTAssertFalse(settings.launchArguments.contains("--stt-model"))
    }

    func testEveryPreloadSelectionRequiresServerRestart() {
        let original = NativSettings()

        for slot in ModelPreloadSlot.allCases {
            var changed = original
            changed.setModelID("org/model", for: slot)

            XCTAssertFalse(
                original.hasSameLaunchConfiguration(as: changed),
                "\(slot.displayName) should participate in restart detection"
            )
        }
    }

    func testCrossKindSelectionWarnsWhenCombinedModelsExceedBudget() {
        let warning = ModelPreloadMemoryWarning.evaluate(
            candidateModelID: "org/image",
            candidateSlot: .imageGeneration,
            currentSelections: [.language: "org/language"],
            workingSetBytesByModelID: [
                "org/language": 60,
                "org/image": 50,
            ],
            memoryBudgetBytes: 100,
            totalMemoryBytes: 125
        )

        XCTAssertEqual(warning?.existingSlots, [.language])
        XCTAssertEqual(warning?.estimatedWorkingSetBytes, 110)
    }

    func testSameKindReplacementDoesNotWarn() {
        let warning = ModelPreloadMemoryWarning.evaluate(
            candidateModelID: "org/new-language",
            candidateSlot: .language,
            currentSelections: [.language: "org/old-language"],
            workingSetBytesByModelID: [
                "org/old-language": 80,
                "org/new-language": 80,
            ],
            memoryBudgetBytes: 100,
            totalMemoryBytes: 125
        )

        XCTAssertNil(warning)
    }

    func testReplacementExcludesPreviousModelInSameSlot() {
        let warning = ModelPreloadMemoryWarning.evaluate(
            candidateModelID: "org/new-language",
            candidateSlot: .language,
            currentSelections: [
                .language: "org/old-language",
                .imageGeneration: "org/image",
            ],
            workingSetBytesByModelID: [
                "org/old-language": 80,
                "org/new-language": 50,
                "org/image": 40,
            ],
            memoryBudgetBytes: 100,
            totalMemoryBytes: 125
        )

        XCTAssertNil(warning)
    }

    func testModelSelectedForTwoKindsIsCountedOnce() {
        let warning = ModelPreloadMemoryWarning.evaluate(
            candidateModelID: "org/multimodal",
            candidateSlot: .imageGeneration,
            currentSelections: [.language: "org/multimodal"],
            workingSetBytesByModelID: ["org/multimodal": 90],
            memoryBudgetBytes: 80,
            totalMemoryBytes: 100
        )

        XCTAssertEqual(warning?.estimatedWorkingSetBytes, 90)
    }
}

extension Array where Element == String {
    fileprivate func containsAdjacent(_ first: String, _ second: String) -> Bool {
        indices.dropLast().contains {
            self[$0] == first && self[index(after: $0)] == second
        }
    }
}
