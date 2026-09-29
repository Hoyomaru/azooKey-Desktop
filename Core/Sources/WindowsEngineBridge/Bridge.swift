import ConverterEngine
import Core
import Foundation

private let bridgeABIVersion: UInt32 = 2

public typealias EngineResponseCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    Int32,
    UnsafePointer<UInt8>?,
    UInt32
) -> Void

private struct BridgeConfiguration: Decodable {
    var protocolVersion: UInt32
    var applicationSupportDirectory: String?
    var memoryDirectory: String?
    var resourcesDirectory: String?
    var sharedContainerDirectory: String?
}

private struct BridgeDiagnosticRequest: Decodable {
    var type: String
    var text: String?
    var inputStyle: String?
}

private struct ConversionSmokeResponse: Encodable {
    var type = "conversion-smoke"
    var convertTarget: String
    var candidates: [String]
}

private struct CallbackTarget: @unchecked Sendable {
    var callback: EngineResponseCallback
    var userData: UnsafeMutableRawPointer?

    func respond(status: Int32, data: Data = Data()) {
        data.withUnsafeBytes { rawBuffer in
            callback(
                userData,
                status,
                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                UInt32(data.count)
            )
        }
    }
}

private final class BridgeEngine: @unchecked Sendable {
    private let configuration: BridgeConfiguration
    private let engine: ConverterEngine

    init(configurationData: Data) throws {
        let configuration = try JSONDecoder().decode(
            BridgeConfiguration.self,
            from: configurationData
        )
        guard configuration.protocolVersion == bridgeABIVersion else {
            throw BridgeError.unsupportedProtocolVersion(configuration.protocolVersion)
        }
        self.configuration = configuration

        let rootDirectory = URL(
            fileURLWithPath: configuration.applicationSupportDirectory
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("azookey-desktop-engine", isDirectory: true)
                    .path,
            isDirectory: true
        )
        let memoryDirectory = URL(
            fileURLWithPath: configuration.memoryDirectory
                ?? rootDirectory.appendingPathComponent("Memory", isDirectory: true).path,
            isDirectory: true
        )
        let resourcesDirectory = configuration.resourcesDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let sharedContainerDirectory = configuration.sharedContainerDirectory.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? rootDirectory

        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: memoryDirectory,
            withIntermediateDirectories: true
        )

        self.engine = ConverterEngine(
            environment: .init(
                applicationSupportDirectoryURL: rootDirectory,
                memoryDirectoryURL: memoryDirectory,
                resourcesDirectoryURL: resourcesDirectory,
                sharedContainerURL: sharedContainerDirectory
            )
        )
    }

    func handle(
        _ request: Data,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        let engine = self.engine
        Task { @MainActor in
            do {
                if let diagnostic = try? JSONDecoder().decode(
                    BridgeDiagnosticRequest.self,
                    from: request
                ) {
                    switch diagnostic.type {
                    case "bridge-smoke":
                        completion(.success(request))
                        return
                    case "conversion-smoke":
                        completion(.success(try await self.runConversionSmoke(diagnostic)))
                        return
                    default:
                        break
                    }
                }

                let command = try ConverterServerCodec.decodeCommand(from: request)
                let response = try await engine.execute(command)
                completion(.success(try ConverterServerCodec.encode(response)))
            } catch {
                completion(.failure(error))
            }
        }
    }

    @MainActor
    private func runConversionSmoke(_ request: BridgeDiagnosticRequest) async throws -> Data {
        let text = request.text ?? "へんかん"
        let sessionID = "windows-bridge-smoke"
        let inputStyle: ConverterInputStyle = request.inputStyle == "roman2kana" ? .roman2kana : .direct
        let activation = ConverterSessionActivation(
            config: ConverterSessionConfig(
                aiBackendPreference: .off,
                openAIModelName: Config.OpenAiModelName.default,
                openAIEndpoint: Config.OpenAiApiEndpoint.default,
                openAIAPIKey: .init(""),
                includeContextInAITransform: true
            ),
            inputLanguage: .japanese
        )

        var response = ConverterServerResponse(snapshot: .empty)
        for (offset, character) in text.map(String.init).enumerated() {
            let keyRequest = ConverterKeyEventRequest(
                eventID: UInt64(offset + 1),
                event: KeyEventCore(
                    modifierFlags: [],
                    characters: character,
                    charactersIgnoringModifiers: character,
                    keyCode: 0
                ),
                inputStyle: inputStyle,
                liveConversionEnabled: false,
                enableDebugWindow: false,
                enableSuggestion: false,
                context: .init(),
                activation: offset == 0 ? activation : nil
            )
            let command: ConverterServerCommand
            if offset == 0 {
                command = .openSession(
                    sessionID: sessionID,
                    command: .handleKeyEvent(keyRequest)
                )
            } else {
                command = .session(
                    sessionID: sessionID,
                    command: .handleKeyEvent(keyRequest)
                )
            }
            response = try await engine.execute(command)
        }

        let candidates: [String]
        switch response.snapshot.candidateWindow {
        case .hidden:
            candidates = []
        case .composing(let presentations, _), .selecting(let presentations, _):
            candidates = presentations.map(\.text)
        }

        _ = engine.removeSession(sessionID)

        return try JSONEncoder().encode(
            ConversionSmokeResponse(
                convertTarget: response.snapshot.convertTarget,
                candidates: candidates
            )
        )
    }
}

private enum BridgeError: LocalizedError {
    case unsupportedProtocolVersion(UInt32)

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocolVersion(let version):
            "Unsupported bridge protocol version: \(version)"
        }
    }
}

@_cdecl("azookey_engine_abi_version")
public func azookeyEngineABIVersion() -> UInt32 {
    bridgeABIVersion
}

@_cdecl("azookey_engine_create")
public func azookeyEngineCreate(
    _ configurationBytes: UnsafePointer<UInt8>?,
    _ configurationLength: UInt32
) -> UnsafeMutableRawPointer? {
    guard let configurationBytes, configurationLength > 0 else {
        return nil
    }
    let configuration = Data(
        bytes: configurationBytes,
        count: Int(configurationLength)
    )
    do {
        return Unmanaged.passRetained(
            try BridgeEngine(configurationData: configuration)
        ).toOpaque()
    } catch {
        return nil
    }
}

@_cdecl("azookey_engine_handle_async")
public func azookeyEngineHandleAsync(
    _ context: UnsafeMutableRawPointer?,
    _ requestBytes: UnsafePointer<UInt8>?,
    _ requestLength: UInt32,
    _ callback: EngineResponseCallback?,
    _ userData: UnsafeMutableRawPointer?
) {
    guard let context, let callback else {
        callback?(userData, -1, nil, 0)
        return
    }

    let request: Data
    if requestLength == 0 {
        request = Data()
    } else {
        guard let requestBytes else {
            callback(userData, -2, nil, 0)
            return
        }
        request = Data(bytes: requestBytes, count: Int(requestLength))
    }

    let target = CallbackTarget(callback: callback, userData: userData)
    let engine = Unmanaged<BridgeEngine>.fromOpaque(context).takeUnretainedValue()
    engine.handle(request) { result in
        switch result {
        case .success(let data):
            target.respond(status: 0, data: data)
        case .failure:
            target.respond(status: -4)
        }
    }
}

@_cdecl("azookey_engine_destroy")
public func azookeyEngineDestroy(_ context: UnsafeMutableRawPointer?) {
    guard let context else {
        return
    }
    Unmanaged<BridgeEngine>.fromOpaque(context).release()
}
