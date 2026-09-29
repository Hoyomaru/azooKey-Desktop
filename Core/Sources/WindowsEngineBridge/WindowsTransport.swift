import Core

let windowsTransportProtocolVersion: UInt32 = 1

enum WindowsTransportOperation: String, Codable {
    case keyEvent
    case snapshot
    case commit
    case stopComposition
    case selectCandidate
    case submitSelectedCandidate
    case closeSession
}

enum WindowsTransportInputLanguage: String, Codable {
    case japanese
    case english

    var core: InputLanguage {
        switch self {
        case .japanese:
            .japanese
        case .english:
            .english
        }
    }

    init(_ language: InputLanguage) {
        switch language {
        case .japanese:
            self = .japanese
        case .english:
            self = .english
        }
    }
}

enum WindowsTransportInputStyle: String, Codable {
    case direct
    case roman2kana
    case defaultRomanToKana
    case defaultAZIK
    case defaultKanaUS
    case defaultKanaJIS
    case empty

    var core: ConverterInputStyle {
        switch self {
        case .direct:
            .direct
        case .roman2kana:
            .roman2kana
        case .defaultRomanToKana:
            .defaultRomanToKana
        case .defaultAZIK:
            .defaultAZIK
        case .defaultKanaUS:
            .defaultKanaUS
        case .defaultKanaJIS:
            .defaultKanaJIS
        case .empty:
            .empty
        }
    }
}

struct WindowsTransportTextContext: Codable {
    var left: String?
    var right: String?

    var core: ConverterTextContext {
        .init(leftSideContext: left, rightSideContext: right)
    }
}

struct WindowsTransportKeyEvent: Codable {
    var eventID: UInt64
    var coreKeyCode: UInt16
    var characters: String?
    var charactersIgnoringModifiers: String?
    var modifierFlags: Int
    var inputStyle: WindowsTransportInputStyle
    var inputLanguage: WindowsTransportInputLanguage
    var activate: Bool
    var liveConversionEnabled: Bool
    var enableDebugWindow: Bool
    var enableSuggestion: Bool
    var enablePredictiveTyping: Bool
    var enableTypoCorrection: Bool
    var enableOptionDirectFullWidthInput: Bool
    var typeBackSlash: Bool
    var optionDirectInputText: String?
    var visibleCandidateStartIndex: Int
    var context: WindowsTransportTextContext

    var core: ConverterKeyEventRequest {
        let activation: ConverterSessionActivation? = activate
            ? .init(
                config: .init(
                    aiBackendPreference: .off,
                    openAIModelName: Config.OpenAiModelName.default,
                    openAIEndpoint: Config.OpenAiApiEndpoint.default,
                    openAIAPIKey: .init(""),
                    includeContextInAITransform: true
                ),
                inputLanguage: inputLanguage.core
            )
            : nil

        return ConverterKeyEventRequest(
            eventID: eventID,
            event: KeyEventCore(
                modifierFlags: .init(rawValue: modifierFlags),
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                keyCode: coreKeyCode
            ),
            inputStyle: inputStyle.core,
            liveConversionEnabled: liveConversionEnabled,
            enableDebugWindow: enableDebugWindow,
            enableSuggestion: enableSuggestion,
            enablePredictiveTyping: enablePredictiveTyping,
            enableTypoCorrection: enableTypoCorrection,
            enableOptionDirectFullWidthInput: enableOptionDirectFullWidthInput,
            typeBackSlash: typeBackSlash,
            optionDirectInputText: optionDirectInputText,
            context: context.core,
            activation: activation,
            visibleCandidateStartIndex: visibleCandidateStartIndex
        )
    }
}

struct WindowsTransportRequest: Codable {
    var protocolVersion: UInt32
    var operation: WindowsTransportOperation
    var sessionID: String
    var keyEvent: WindowsTransportKeyEvent?
    var candidateIndex: Int?
    var context: WindowsTransportTextContext?

    enum Action {
        case command(ConverterServerCommand)
        case closeSession(String)
    }

    func action() throws -> Action {
        guard protocolVersion == windowsTransportProtocolVersion else {
            throw WindowsTransportError.unsupportedProtocolVersion(protocolVersion)
        }

        switch operation {
        case .keyEvent:
            guard let keyEvent else {
                throw WindowsTransportError.missingField("keyEvent")
            }
            let sessionCommand = ConverterSessionCommand.handleKeyEvent(keyEvent.core)
            if keyEvent.activate {
                return .command(
                    .openSession(sessionID: sessionID, command: sessionCommand)
                )
            }
            return .command(.session(sessionID: sessionID, command: sessionCommand))
        case .snapshot:
            return .command(
                .session(sessionID: sessionID, command: .composition(.snapshot))
            )
        case .commit:
            return .command(
                .session(sessionID: sessionID, command: .composition(.commit))
            )
        case .stopComposition:
            return .command(
                .session(sessionID: sessionID, command: .composition(.stopComposition))
            )
        case .selectCandidate:
            guard let candidateIndex else {
                throw WindowsTransportError.missingField("candidateIndex")
            }
            return .command(
                .session(
                    sessionID: sessionID,
                    command: .candidate(.selectCandidate(index: candidateIndex))
                )
            )
        case .submitSelectedCandidate:
            return .command(
                .session(
                    sessionID: sessionID,
                    command: .candidate(
                        .submitSelectedCandidate(
                            context: (context ?? .init(left: nil, right: nil)).core
                        )
                    )
                )
            )
        case .closeSession:
            return .closeSession(sessionID)
        }
    }
}

struct WindowsTransportResponse: Codable {
    var protocolVersion = windowsTransportProtocolVersion
    var handled: Bool
    var inputState: State
    var inputLanguage: WindowsTransportInputLanguage?
    var effects: [Effect]
    var markedText: MarkedText
    var candidateWindow: CandidateWindow
    var predictionCandidates: [PredictionCandidate]
    var isEmpty: Bool
    var convertTarget: String

    struct State: Codable {
        var kind: String
        var value: String?

        init(_ state: ConverterInputState) {
            switch state {
            case .none:
                self.init(kind: "none", value: nil)
            case .attachDiacritic(let value):
                self.init(kind: "attachDiacritic", value: value)
            case .composing:
                self.init(kind: "composing", value: nil)
            case .previewing:
                self.init(kind: "previewing", value: nil)
            case .selecting:
                self.init(kind: "selecting", value: nil)
            case .replaceSuggestion:
                self.init(kind: "replaceSuggestion", value: nil)
            case .unicodeInput(let value):
                self.init(kind: "unicodeInput", value: value)
            }
        }

        init(kind: String, value: String?) {
            self.kind = kind
            self.value = value
        }
    }

    struct Effect: Codable {
        var type: String
        var text: String?
        var secondaryText: String?
        var inputLanguage: WindowsTransportInputLanguage?

        init(_ effect: ConverterClientEffect) {
            switch effect {
            case .insertText(let text):
                self.init(type: "insertText", text: text)
            case .switchInputLanguage(let language):
                self.init(
                    type: "switchInputLanguage",
                    inputLanguage: .init(language)
                )
            case .requestPredictiveSuggestion:
                self.init(type: "requestPredictiveSuggestion")
            case .requestReplaceSuggestion:
                self.init(type: "requestReplaceSuggestion")
            case .selectNextReplaceSuggestionCandidate:
                self.init(type: "selectNextReplaceSuggestionCandidate")
            case .selectPreviousReplaceSuggestionCandidate:
                self.init(type: "selectPreviousReplaceSuggestionCandidate")
            case .submitReplaceSuggestionCandidate:
                self.init(type: "submitReplaceSuggestionCandidate")
            case .hideReplaceSuggestionWindow:
                self.init(type: "hideReplaceSuggestionWindow")
            case .showPromptInputWindow:
                self.init(type: "showPromptInputWindow")
            case .transformSelectedText(let first, let second):
                self.init(
                    type: "transformSelectedText",
                    text: first,
                    secondaryText: second
                )
            case .fallthroughToApplication:
                self.init(type: "fallthroughToApplication")
            }
        }

        init(
            type: String,
            text: String? = nil,
            secondaryText: String? = nil,
            inputLanguage: WindowsTransportInputLanguage? = nil
        ) {
            self.type = type
            self.text = text
            self.secondaryText = secondaryText
            self.inputLanguage = inputLanguage
        }
    }

    struct MarkedText: Codable {
        var elements: [Element]
        var selectionLocation: Int
        var selectionLength: Int

        struct Element: Codable {
            var content: String
            var focus: String
        }

        init(_ markedText: ConverterMarkedText) {
            self.elements = markedText.elements.map {
                Element(
                    content: $0.content,
                    focus: switch $0.focus {
                    case .focused: "focused"
                    case .unfocused: "unfocused"
                    case .none: "none"
                    }
                )
            }
            self.selectionLocation = markedText.selectionRange.location
            self.selectionLength = markedText.selectionRange.length
        }
    }

    struct Candidate: Codable {
        var text: String
        var annotationText: String?
        var extraValues: [String: String]

        init(_ candidate: ConverterCandidatePresentation) {
            self.text = candidate.text
            self.annotationText = candidate.annotationText
            self.extraValues = candidate.extraValues
        }
    }

    struct CandidateWindow: Codable {
        var kind: String
        var candidates: [Candidate]
        var selectionIndex: Int?

        init(_ window: ConverterCandidateWindow) {
            switch window {
            case .hidden:
                self.init(kind: "hidden", candidates: [], selectionIndex: nil)
            case .composing(let candidates, let selectionIndex):
                self.init(
                    kind: "composing",
                    candidates: candidates.map(Candidate.init),
                    selectionIndex: selectionIndex
                )
            case .selecting(let candidates, let selectionIndex):
                self.init(
                    kind: "selecting",
                    candidates: candidates.map(Candidate.init),
                    selectionIndex: selectionIndex
                )
            }
        }

        init(kind: String, candidates: [Candidate], selectionIndex: Int?) {
            self.kind = kind
            self.candidates = candidates
            self.selectionIndex = selectionIndex
        }
    }

    struct PredictionCandidate: Codable {
        var displayText: String
        var appendText: String
        var deleteCount: Int

        init(_ candidate: ConverterPredictionCandidate) {
            self.displayText = candidate.displayText
            self.appendText = candidate.appendText
            self.deleteCount = candidate.deleteCount
        }
    }

    init(_ response: ConverterServerResponse) {
        self.handled = response.handled
        self.inputState = State(response.inputState)
        self.inputLanguage = response.inputLanguage.map(WindowsTransportInputLanguage.init)
        self.effects = response.effects.map(Effect.init)
        self.markedText = MarkedText(response.snapshot.markedText)
        self.candidateWindow = CandidateWindow(response.snapshot.candidateWindow)
        self.predictionCandidates = response.snapshot.predictionCandidates.map(PredictionCandidate.init)
        self.isEmpty = response.snapshot.isEmpty
        self.convertTarget = response.snapshot.convertTarget
    }

    static var closedSession: WindowsTransportResponse {
        WindowsTransportResponse(
            handled: true,
            inputState: State(kind: "none", value: nil),
            inputLanguage: nil,
            effects: [],
            markedText: MarkedText(
                ConverterMarkedText(
                    elements: [],
                    selectionRange: .init(location: 0, length: 0)
                )
            ),
            candidateWindow: CandidateWindow(kind: "hidden", candidates: [], selectionIndex: nil),
            predictionCandidates: [],
            isEmpty: true,
            convertTarget: ""
        )
    }

    private init(
        handled: Bool,
        inputState: State,
        inputLanguage: WindowsTransportInputLanguage?,
        effects: [Effect],
        markedText: MarkedText,
        candidateWindow: CandidateWindow,
        predictionCandidates: [PredictionCandidate],
        isEmpty: Bool,
        convertTarget: String
    ) {
        self.handled = handled
        self.inputState = inputState
        self.inputLanguage = inputLanguage
        self.effects = effects
        self.markedText = markedText
        self.candidateWindow = candidateWindow
        self.predictionCandidates = predictionCandidates
        self.isEmpty = isEmpty
        self.convertTarget = convertTarget
    }
}

enum WindowsTransportError: LocalizedError {
    case unsupportedProtocolVersion(UInt32)
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocolVersion(let version):
            "Unsupported Windows transport protocol version: \(version)"
        case .missingField(let field):
            "Missing Windows transport field: \(field)"
        }
    }
}
