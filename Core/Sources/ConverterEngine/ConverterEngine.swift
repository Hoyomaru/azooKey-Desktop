import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

public final class ConverterEngine: @unchecked Sendable {
    private static let learningDataCommitDelay: TimeInterval = 2

    private var sessions: [String: ConverterSession] = [:]
    private let kanaKanjiConverter = KanaKanjiConverter.withDefaultDictionary()
    private let learningDataCommitScheduler = DebouncedActionScheduler()
    private let environment: ConverterEngineEnvironment
    private let shutdownHandler: @Sendable () -> Void

    public init(
        environment: ConverterEngineEnvironment,
        shutdownHandler: @escaping @Sendable () -> Void = {}
    ) {
        self.environment = environment
        self.shutdownHandler = shutdownHandler
    }

    @MainActor
    public func execute(_ command: ConverterServerCommand) async throws -> ConverterServerResponse {
        defer { learningDataCommitScheduler.postponeIfScheduled(after: Self.learningDataCommitDelay) }
        switch command {
        case .shutdown:
            shutdownHandler()
            return ConverterServerResponse(snapshot: .empty)
        case .maintenance(let command):
            return try handle(command)
        case .openSession(let sessionID, let command):
            createSessionIfNeeded(sessionID)
            return try await handle(command, sessionID: sessionID)
        case .session(let sessionID, let command):
            return try await handle(command, sessionID: sessionID)
        }
    }

    @MainActor
    private func createSessionIfNeeded(_ sessionID: String) {
        guard sessions[sessionID] == nil else {
            return
        }
        let conversionSessionID = kanaKanjiConverter.createSession()
        sessions[sessionID] = ConverterSession(
            manager: Self.makeSegmentsManager(
                kanaKanjiConverter: kanaKanjiConverter,
                environment: environment
            ),
            conversionSessionID: conversionSessionID
        )
    }

    @MainActor
    private func handle(_ command: ConverterMaintenanceCommand) throws -> ConverterServerResponse {
        switch command {
        case .synchronizeUserDictionary(let forceExport):
            let memoryDirectoryURL = environment.memoryDirectoryURL
            if forceExport || !CompiledUserDictionaryStore.hasExportedDictionary(memoryDirectoryURL: memoryDirectoryURL) {
                try CompiledUserDictionaryStore.exportCurrentDictionaries(memoryDirectoryURL: memoryDirectoryURL)
            }
            kanaKanjiConverter.updateUserDictionaryURL(
                CompiledUserDictionaryStore.directoryURL(memoryDirectoryURL: memoryDirectoryURL),
                forceReload: true
            )
        case .resetLearningData:
            kanaKanjiConverter.resetMemory()
        }
        return ConverterServerResponse(snapshot: .empty)
    }

    @MainActor
    private func handle(_ command: ConverterSessionCommand, sessionID: String) async throws -> ConverterServerResponse {
        let session = try getSession(sessionID)
        switch command {
        case .lifecycle(let command):
            return try withConverterSession(session) {
                handle(command, session: session)
            }
        case .settings(let command):
            return try withConverterSession(session) {
                try handle(command, session: session)
            }
        case .updateConfig(let config):
            return try withConverterSession(session) {
                session.config = config
                return makeResponse(for: session, inputState: .none)
            }
        case .handleKeyEvent(let request):
            return try withConverterSession(session) {
                try handleKeyEvent(sessionID: sessionID, request: request)
            }
        case .composition(let command):
            return try withConverterSession(session) {
                handle(command, session: session)
            }
        case .candidate(let command):
            return try withConverterSession(session) {
                handle(command, session: session)
            }
        case .replaceSuggestion(let command):
            return try await handle(command, session: session)
        }
    }

    @MainActor
    private func withConverterSession<Result>(
        _ session: ConverterSession,
        operation: () throws -> Result
    ) throws -> Result {
        try kanaKanjiConverter.withSession(session.conversionSessionID, operation: operation)
    }

    @MainActor
    private func handle(
        _ command: ConverterSessionLifecycleCommand,
        session: ConverterSession
    ) -> ConverterServerResponse {
        switch command {
        case .activate:
            session.manager.activate()
            return makeResponse(for: session, inputState: session.inputState)
        case .deactivate:
            // アプリ切替直後のキー入力を、学習データの同期I/Oで塞がない。
            // 共有Converterはプロセス内に残るため、永続化だけ入力のアイドル時まで遅延できる。
            session.manager.deactivate(flushLearningData: false)
            scheduleLearningDataCommit()
            session.inputState = .none
            session.clearReplaceSuggestions()
            return makeResponse(for: session, inputState: session.inputState)
        case .synchronizeInputLanguage(let language):
            session.inputLanguage = language
            if language == .english {
                session.manager.stopJapaneseInput()
            }
            return makeResponse(
                for: session,
                inputState: session.inputState
            )
        }
    }

    @MainActor
    private func handle(
        _ command: ConverterSettingsCommand,
        session: ConverterSession
    ) throws -> ConverterServerResponse {
        switch command {
        case .list(let capabilities):
            return makeResponse(
                for: session,
                inputState: .none,
                settings: Self.makeSettingDescriptors(capabilities: capabilities)
            )
        case .update(let key, let value):
            try Self.updateSetting(key: key, value: value)
            return makeResponse(for: session, inputState: .none)
        }
    }

    @MainActor
    private func handle(
        _ command: ConverterCompositionCommand,
        session: ConverterSession
    ) -> ConverterServerResponse {
        switch command {
        case .snapshot:
            return makeResponse(for: session, inputState: session.inputState)
        case .stopComposition:
            session.manager.stopComposition()
            session.inputState = .none
            return makeResponse(for: session, inputState: session.inputState)
        case .forgetMemory:
            session.manager.forgetMemory()
            return makeResponse(for: session, inputState: session.inputState)
        case .commit:
            let text = session.manager.commitMarkedText(inputState: session.inputState)
            let effects: [ConverterClientEffect] = text.isEmpty ? [] : [.insertText(text)]
            session.inputState = .none
            return makeResponse(
                for: session,
                inputState: session.inputState,
                effects: effects,
                responseInputState: ConverterInputState.none
            )
        }
    }

    @MainActor
    private func handle(
        _ command: ConverterCandidateCommand,
        session: ConverterSession
    ) -> ConverterServerResponse {
        switch command {
        case .selectCandidate(let index):
            session.manager.requestSelectingRow(index)
            session.inputState = .selecting
            return makeResponse(for: session, inputState: session.inputState)
        case .submitSelectedCandidate(let context):
            session.setContext(context)
            var effects: [ConverterClientEffect] = []
            submitSelectedCandidate(
                manager: session.manager,
                leftSideContext: session.conversionLeftSideContext(),
                effects: &effects
            )
            let nextInputState: InputState = session.manager.isEmpty ? .none : .previewing
            session.inputState = nextInputState
            return makeResponse(
                for: session,
                inputState: nextInputState,
                effects: effects,
                responseInputState: ConverterInputState(nextInputState)
            )
        }
    }

    @MainActor
    private func handle(
        _ command: ConverterReplaceSuggestionCommand,
        session: ConverterSession
    ) async throws -> ConverterServerResponse {
        switch command {
        case .request(let context):
            session.setContext(context)
            try await requestReplaceSuggestion(session: session)
            return try withConverterSession(session) {
                session.inputState = .replaceSuggestion
                return makeResponse(
                    for: session,
                    inputState: session.inputState,
                    responseInputState: .replaceSuggestion
                )
            }
        case .selectReplaceSuggestionCandidate(let index):
            return try withConverterSession(session) {
                session.selectReplaceSuggestion(at: index)
                session.inputState = .replaceSuggestion
                return makeResponse(
                    for: session,
                    inputState: session.inputState,
                    responseInputState: .replaceSuggestion
                )
            }
        case .submitSelectedReplaceSuggestion:
            return try withConverterSession(session) {
                var effects: [ConverterClientEffect] = []
                let didSubmit = submitSelectedReplaceSuggestion(session: session, effects: &effects)
                let nextInputState: InputState = didSubmit ? .none : .replaceSuggestion
                session.inputState = nextInputState
                return makeResponse(
                    for: session,
                    inputState: nextInputState,
                    effects: effects,
                    responseInputState: ConverterInputState(nextInputState)
                )
            }
        }
    }

    @MainActor
    private func scheduleLearningDataCommit() {
        learningDataCommitScheduler.schedule(after: Self.learningDataCommitDelay) { [weak self] in
            self?.kanaKanjiConverter.commitUpdateLearningData()
        }
    }

    @MainActor
    @discardableResult
    public func removeSession(_ sessionID: String) -> Bool {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return false
        }
        kanaKanjiConverter.removeSession(session.conversionSessionID)
        scheduleLearningDataCommit()
        return true
    }

    @MainActor
    func getSession(_ sessionID: String) throws -> ConverterSession {
        guard let session = sessions[sessionID] else {
            throw ConverterServerError.unknownSession(sessionID)
        }
        return session
    }

}
