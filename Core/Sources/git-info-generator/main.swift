import Foundation

var tag = try? shell(
    "git for-each-ref refs/tags --points-at HEAD --sort=-creatordate --format=%(refname:short)"
)
    .split(whereSeparator: \.isNewline)
    .first
    .map(String.init)
var commit = try? shell("git rev-parse HEAD")
if tag?.isEmpty == true {
    tag = nil
}
if commit?.isEmpty == true {
    commit = nil
}

let outputPath = CommandLine.arguments[1]
let contents = """
// This file is auto-generated.

let gitTagFromPlugin: String? = \(tag as String?)
let gitCommitFromPlugin: String? = \(commit as String?)
"""

try contents.write(toFile: outputPath, atomically: true, encoding: .utf8)

@discardableResult
func shell(_ command: String) throws -> String {
    let process = Process()
    let pipe = Pipe()

    process.standardOutput = pipe
#if os(Windows)
    process.executableURL = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["COMSPEC"]
            ?? #"C:\Windows\System32\cmd.exe"#
    )
    process.arguments = ["/C", command]
#else
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
#endif

    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "GitInfoGenerator",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "Command failed: \(command)"]
        )
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
