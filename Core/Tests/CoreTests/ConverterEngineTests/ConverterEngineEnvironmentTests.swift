@testable import Core
import Foundation
import Testing

@Test func converterEngineEnvironmentKeepsHostProvidedLocations() {
    let root = URL(fileURLWithPath: "/tmp/azookey-test", isDirectory: true)
    let environment = ConverterEngineEnvironment(
        applicationSupportDirectoryURL: root.appendingPathComponent("support", isDirectory: true),
        memoryDirectoryURL: root.appendingPathComponent("memory", isDirectory: true),
        resourcesDirectoryURL: root.appendingPathComponent("resources", isDirectory: true),
        sharedContainerURL: root.appendingPathComponent("shared", isDirectory: true)
    )

    #expect(environment.applicationSupportDirectoryURL.lastPathComponent == "support")
    #expect(environment.memoryDirectoryURL.lastPathComponent == "memory")
    #expect(environment.resourcesDirectoryURL?.lastPathComponent == "resources")
    #expect(environment.sharedContainerURL?.lastPathComponent == "shared")
}
