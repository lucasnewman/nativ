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
}

extension Array where Element == String {
    fileprivate func containsAdjacent(_ first: String, _ second: String) -> Bool {
        indices.dropLast().contains {
            self[$0] == first && self[index(after: $0)] == second
        }
    }
}
