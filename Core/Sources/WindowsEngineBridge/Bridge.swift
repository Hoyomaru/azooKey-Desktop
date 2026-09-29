import Core
import Foundation

private let bridgeABIVersion: UInt32 = 1

private final class BridgeEngine {
    private let configuration: Data

    init(configuration: Data) {
        self.configuration = configuration
    }

    func handle(_ request: Data) -> Data {
        // The first bridge milestone validates DLL loading, lifetime and byte transport.
        // The next step replaces this echo with the shared desktop converter engine.
        _ = configuration
        return request
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
    let response = engine.handle(request)

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
