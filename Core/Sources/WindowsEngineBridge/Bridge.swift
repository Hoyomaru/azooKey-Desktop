import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

private let bridgeABIVersion: UInt32 = 1

private struct BridgeRequest: Decodable {
    var type: String
    var text: String?
    var inputStyle: String?
}

private struct ConversionSmokeResponse: Encodable {
    var type = "conversion-smoke"
    var candidates: [String]
}

private final class BridgeEngine {
    private let configuration: Data
    private let converter = KanaKanjiConverter.withDefaultDictionary()
    private let memoryDirectoryURL: URL

    init(configuration: Data) {
        self.configuration = configuration
        self.memoryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("azookey-desktop-engine", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: self.memoryDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func handle(_ request: Data) throws -> Data {
        guard let bridgeRequest = try? JSONDecoder().decode(BridgeRequest.self, from: request),
              bridgeRequest.type == "conversion-smoke",
              let text = bridgeRequest.text
        else {
            // Keep unknown requests byte-for-byte compatible while the complete
            // ConverterServer command host is being moved into the shared engine.
            _ = configuration
            return request
        }

        var composingText = ComposingText()
        composingText.insertAtCursorPosition(
            text,
            inputStyle: bridgeRequest.inputStyle == "roman2kana" ? .roman2kana : .direct
        )

        let conversionStartedAt = Date()
        print("[WindowsEngineBridge] requestCandidates begin")

        let result = converter.requestCandidates(
            composingText,
            options: .init(
                N_best: 5,
                requireJapanesePrediction: .disabled,
                requireEnglishPrediction: .disabled,
                keyboardLanguage: .ja_JP,
                englishCandidateInRoman2KanaInput: false,
                fullWidthRomanCandidate: false,
                halfWidthKanaCandidate: false,
                learningType: .nothing,
                maxMemoryCount: 65536,
                shouldResetMemory: false,
                memoryDirectoryURL: memoryDirectoryURL,
                sharedContainerURL: memoryDirectoryURL,
                textReplacer: .empty,
                specialCandidateProviders: [],
                metadata: .init(versionString: "azooKey Windows bridge")
            )
        )

        print(
            "[WindowsEngineBridge] requestCandidates end:",
            Date().timeIntervalSince(conversionStartedAt),
            "seconds"
        )

        return try JSONEncoder().encode(
            ConversionSmokeResponse(candidates: result.mainResults.prefix(10).map(\.text))
        )
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
    let configuration: Data
    if configurationLength == 0 {
        configuration = Data()
    } else {
        guard let configurationBytes else {
            return nil
        }
        configuration = Data(bytes: configurationBytes, count: Int(configurationLength))
    }

    return Unmanaged.passRetained(BridgeEngine(configuration: configuration)).toOpaque()
}

@_cdecl("azookey_engine_handle")
public func azookeyEngineHandle(
    _ context: UnsafeMutableRawPointer?,
    _ requestBytes: UnsafePointer<UInt8>?,
    _ requestLength: UInt32,
    _ responseBytes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    _ responseLength: UnsafeMutablePointer<UInt32>?
) -> Int32 {
    guard let context, let responseBytes, let responseLength else {
        return -1
    }

    let request: Data
    if requestLength == 0 {
        request = Data()
    } else {
        guard let requestBytes else {
            return -2
        }
        request = Data(bytes: requestBytes, count: Int(requestLength))
    }

    let engine = Unmanaged<BridgeEngine>.fromOpaque(context).takeUnretainedValue()
    let response: Data
    do {
        response = try engine.handle(request)
    } catch {
        return -4
    }

    guard response.count <= Int(UInt32.max) else {
        return -3
    }

    responseLength.pointee = UInt32(response.count)
    guard !response.isEmpty else {
        responseBytes.pointee = nil
        return 0
    }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: response.count)
    response.copyBytes(to: buffer, count: response.count)
    responseBytes.pointee = buffer
    return 0
}

@_cdecl("azookey_engine_free")
public func azookeyEngineFree(
    _ bytes: UnsafeMutablePointer<UInt8>?,
    _ length: UInt32
) {
    _ = length
    bytes?.deallocate()
}

@_cdecl("azookey_engine_destroy")
public func azookeyEngineDestroy(_ context: UnsafeMutableRawPointer?) {
    guard let context else {
        return
    }
    Unmanaged<BridgeEngine>.fromOpaque(context).release()
}
