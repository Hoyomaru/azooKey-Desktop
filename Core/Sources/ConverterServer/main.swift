import ConverterEngine
import Core
import Darwin
import Foundation

private enum ConverterServerXPC {
    static let machServiceName = "dev.ensan.inputmethod.azooKeyMac.ConverterServer"
}

@objc private protocol ConverterServerXPCProtocol {
    func openSession(with reply: @escaping @Sendable (String) -> Void)
    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void)
    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void)
    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void)
}

private final class ConverterServer: NSObject, ConverterServerXPCProtocol, @unchecked Sendable {
    private let engine: ConverterEngine

    override init() {
        let environment = ConverterEngineEnvironment.macOSDefault(
            resourcesDirectoryURL: Self.appResourcesDirectoryURL()
        )
        self.engine = ConverterEngine(
            environment: environment,
            shutdownHandler: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    exit(EXIT_SUCCESS)
                }
            }
        )
        super.init()
    }

    func openSession(with reply: @escaping @Sendable (String) -> Void) {
        Task(priority: .userInitiated) { @MainActor in
            let sessionID = UUID().uuidString
            do {
                _ = try await self.engine.execute(
                    .openSession(
                        sessionID: sessionID,
                        command: .composition(.snapshot)
                    )
                )
                reply(sessionID)
            } catch {
                reply("")
            }
        }
    }

    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void) {
        Task { @MainActor in
            reply(self.engine.removeSession(sessionID))
        }
    }

    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void) {
        reply("ConverterServer: \(message)")
    }

    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void) {
        Task(priority: .userInitiated) { @MainActor in
            do {
                let command = try ConverterServerCodec.decodeCommand(from: data)
                let response = try await self.engine.execute(command)
                reply(try ConverterServerCodec.encode(response), nil)
            } catch {
                reply(nil, error.localizedDescription as NSString)
            }
        }
    }

    private static func appResourcesDirectoryURL() -> URL {
        if let executableURL = Bundle.main.executableURL {
            var directoryURL = executableURL.deletingLastPathComponent()
            while directoryURL.path != "/" {
                if directoryURL.lastPathComponent == "Contents" {
                    return directoryURL.appendingPathComponent("Resources", isDirectory: true)
                }
                directoryURL.deleteLastPathComponent()
            }
        }
        if let resourceURL = Bundle.main.resourceURL {
            return resourceURL
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    }
}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let server = ConverterServer()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.exportedObject = server
        connection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: ConverterServerXPC.machServiceName)
private let delegate = ServiceDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
