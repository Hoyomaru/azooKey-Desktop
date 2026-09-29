import Core
import Foundation

let windowsBridgeProtocolVersion: UInt32 = 1

enum WindowsBridgeOperation: String, Codable {
    case keyEvent
    case snapshot
    case commit
    case stopComposition
    case closeSession
}

enum WindowsBridgeLanguage: String, Codable {
    case japanese
    case english

    var inputLanguage: InputLanguage {
        switch self {
        case .japanese: .japanese
        case .english: .english
        }
    }

    init(_ language: InputLanguage) {
        switch language {
        case .japanese: self = .japanese
        case .english: self = .english
        }
    }
}

enum WindowsBridgeInputStyle: String, Codable {
    case direct
    case roman2kana
    case defaultRomanToKana
    case defaultAZIK
    case defaultKanaUS
    case defaultKanaJIS
    case empty

    var converterInputStyle: ConverterInputStyle {
        switch self {
        case .direct: .direct
        case .roman2kana: .roman2kana
        case .defaultRomanToKana: .defaultRomanToKana
        case .defaultAZIK: .defaultAZIK
        case .defaultKanaUS: .defaultKanaUS
        case .defaultKanaJIS: .defaultKanaJIS
        case .empty: .empty
        }
    }
}

struct WindowsBridgeTextContext: Codable {
    var left: String?
    var right: String?

    var converterContext: ConverterTextContext {
        ConverterTextContext(
            leftSideContext: left,
            rightSideContext: right
        )
    }
}

struct WindowsBridgeKeyEvent: Codable {
    var eventID: UInt64
    var modifierFlags: Int
    var characters: String?
    var charactersIgnoringModifiers: String?
    var keyCode: UInt16
}

struct WindowsBridgeRequest: Codable {
    var windowsBridgeVersion: UInt32
    var operation: WindowsBridgeOperation
    var sessionID: String

    var activate: Bool?
    var language: WindowsBridgeLanguage?
    var inputStyle: WindowsBridgeInputStyle?
    var liveConversionEnabled: Bool?
    var enableSuggestion: Bool?
    var enablePredictiveTyping: Bool?
    var enableTypoCorrection: Bool?
    var typeBackSlash: Bool?
    var visibleCandidateStartIndex: Int?

    var event: WindowsBridgeKeyEvent?
    var context: WindowsBridgeTextContext?
}

struct WindowsBridgeMarkedTextElement: Codable {
    var text: String
    var focus: String
}

struct WindowsBridgeCandidate: Codable {
    var text: String
    var annotation: String?
}

struct WindowsBridgeCandidateWindow: Codable {
    var state: String
    var candidates: [WindowsBridgeCandidate]
    var selectionIndex: Int?
}

struct WindowsBridgeEffect: Codable {
    var kind: String
    var text: String?
    var secondaryText: String?
    var language: WindowsBridgeLanguage?
}

struct WindowsBridgeResponse: Codable {
    var windowsBridgeVersion = windowsBridgeProtocolVersion
    var handled: Bool
    var inputState: String
    var inputStateValue: String?
    var inputLanguage: WindowsBridgeLanguage?

    var markedText: [WindowsBridgeMarkedTextElement]
    var selectionLocation: Int
    var selectionLength: Int

    var candidateWindow: WindowsBridgeCandidateWindow
    var effects: [WindowsBridgeEffect]

    var isEmpty: Bool
    var convertTarget: String

    init(_ response: ConverterServerResponse) {
        self.handled = response.handled
        self.inputLanguage = response.inputLanguage.map(WindowsBridgeLanguage.init)

        switch response.inputState {
        case .none:
            self.inputState = "none"
            self.inputStateValue = nil
        case .attachDiacritic(let value):
            self.inputState = "attachDiacritic"
            self.inputStateValue = value
        case .composing:
            self.inputState = "composing"
            self.inputStateValue = nil
        case .previewing:
            self.inputState = "previewing"
            self.inputStateValue = nil
        case .selecting:
            self.inputState = "selecting"
            self.inputStateValue = nil
        case .replaceSuggestion:
            self.inputState = "replaceSuggestion"
            self.inputStateValue = nil
        case .unicodeInput(let value):
            self.inputState = "unicodeInput"
            self.inputStateValue = value
        }

        self.markedText = response.snapshot.markedText.elements.map { element in
            let focus: String = switch element.focus {
            case .focused: "focused"
            case .unfocused: "unfocused"
            case .none: "none"
            }
            return WindowsBridgeMarkedTextElement(
                text: element.content,
                focus: focus
            )
        }
        self.selectionLocation = response.snapshot.markedText.selectionRange.location
        self.selectionLength = response.snapshot.markedText.selectionRange.length

        switch response.snapshot.candidateWindow {
        case .hidden:
            self.candidateWindow = WindowsBridgeCandidateWindow(
                state: "hidden",
                candidates: [],
                selectionIndex: nil
            )
        case .composing(let candidates, let selectionIndex):
            self.candidateWindow = WindowsBridgeCandidateWindow(
                state: "composing",
                candidates: candidates.map {
                    WindowsBridgeCandidate(text: $0.text, annotation: $0.annotationText)
                },
                selectionIndex: selectionIndex
            )
        case .selecting(let candidates, let selectionIndex):
            self.candidateWindow = WindowsBridgeCandidateWindow(
                state: "selecting",
                candidates: candidates.map {
                    WindowsBridgeCandidate(text: $0.text, annotation: $0.annotationText)
                },
                selectionIndex: selectionIndex
            )
        }

        self.effects = response.effects.map(WindowsBridgeEffect.init)
        self.isEmpty = response.snapshot.isEmpty
        self.convertTarget = response.snapshot.convertTarget
    }

    static var closedSession: WindowsBridgeResponse {
        WindowsBridgeResponse(
            handled: true,
            inputState: "none",
            inputStateValue: nil,
            inputLanguage: nil,
            markedText: [],
            selectionLocation: -1,
            selectionLength: -1,
            candidateWindow: .init(
                state: "hidden",
                candidates: [],
                selectionIndex: nil
            ),
            effects: [],
            isEmpty: true,
            convertTarget: ""
        )
    }

    private init(
        handled: Bool,
        inputState: String,
        inputStateValue: String?,
        inputLanguage: WindowsBridgeLanguage?,
        markedText: [WindowsBridgeMarkedTextElement],
        selectionLocation: Int,
        selectionLength: Int,
        candidateWindow: WindowsBridgeCandidateWindow,
        effects: [WindowsBridgeEffect],
        isEmpty: Bool,
        convertTarget: String
    ) {
        self.handled = handled
        self.inputState = inputState
        self.inputStateValue = inputStateValue
        self.inputLanguage = inputLanguage
        self.markedText = markedText
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
        self.candidateWindow = candidateWindow
        self.effects = effects
        self.isEmpty = isEmpty
        self.convertTarget = convertTarget
    }
}

private extension WindowsBridgeEffect {
    init(_ effect: ConverterClientEffect) {
        switch effect {
        case .insertText(let text):
            self = .init(kind: "insertText", text: text)
        case .switchInputLanguage(let language):
            self = .init(
                kind: "switchInputLanguage",
                language: WindowsBridgeLanguage(language)
            )
        case .requestPredictiveSuggestion:
            self = .init(kind: "requestPredictiveSuggestion")
        case .requestReplaceSuggestion:
            self = .init(kind: "requestReplaceSuggestion")
        case .selectNextReplaceSuggestionCandidate:
            self = .init(kind: "selectNextReplaceSuggestionCandidate")
        case .selectPreviousReplaceSuggestionCandidate:
            self = .init(kind: "selectPreviousReplaceSuggestionCandidate")
        case .submitReplaceSuggestionCandidate:
            self = .init(kind: "submitReplaceSuggestionCandidate")
        case .hideReplaceSuggestionWindow:
            self = .init(kind: "hideReplaceSuggestionWindow")
        case .showPromptInputWindow:
            self = .init(kind: "showPromptInputWindow")
        case .transformSelectedText(let text, let prompt):
            self = .init(
                kind: "transformSelectedText",
                text: text,
                secondaryText: prompt
            )
        case .fallthroughToApplication:
            self = .init(kind: "fallthroughToApplication")
        }
    }

    init(
        kind: String,
        text: String? = nil,
        secondaryText: String? = nil,
        language: WindowsBridgeLanguage? = nil
    ) {
        self.kind = kind
        self.text = text
        self.secondaryText = secondaryText
        self.language = language
    }
}
