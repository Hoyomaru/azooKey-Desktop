import Foundation

/// Host-provided filesystem and resource locations used by the desktop conversion engine.
///
/// Keeping these locations explicit prevents shared conversion logic from depending on
/// macOS App Groups or Windows-specific directory discovery. Platform hosts are
/// responsible for resolving their native paths and injecting them here.
public struct ConverterEngineEnvironment: Sendable, Equatable {
    public var applicationSupportDirectoryURL: URL
    public var memoryDirectoryURL: URL
    public var resourcesDirectoryURL: URL?
    public var sharedContainerURL: URL?

    public init(
        applicationSupportDirectoryURL: URL,
        memoryDirectoryURL: URL,
        resourcesDirectoryURL: URL? = nil,
        sharedContainerURL: URL? = nil
    ) {
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.memoryDirectoryURL = memoryDirectoryURL
        self.resourcesDirectoryURL = resourcesDirectoryURL
        self.sharedContainerURL = sharedContainerURL
    }
}

#if os(macOS)
public extension ConverterEngineEnvironment {
    /// Current macOS layout, expressed through the host-independent environment type.
    ///
    /// This is intentionally the only place in this type that knows about AppGroup.
    /// A Windows host should construct the environment with explicit Windows paths.
    static func macOSDefault(
        fileManager: FileManager = .default,
        resourcesDirectoryURL: URL? = Bundle.main.resourceURL
    ) -> Self {
        Self(
            applicationSupportDirectoryURL: AppGroup.applicationSupportDirectoryURL(fileManager: fileManager),
            memoryDirectoryURL: AppGroup.memoryDirectoryURL(fileManager: fileManager),
            resourcesDirectoryURL: resourcesDirectoryURL,
            sharedContainerURL: AppGroup.containerURL(fileManager: fileManager)
        )
    }
}
#endif
