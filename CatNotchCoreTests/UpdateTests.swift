import Foundation
import Testing
@testable import CatNotchCore

private let feed = """
version: 2.0.1
files:
  - url: CatNotch-2.0.1-universal-mac.zip
    sha512: dW5p
    size: 100
  - url: CatNotch-2.0.1-arm64-mac.zip
    sha512: "YXJt"
    size: 90
path: CatNotch-2.0.1-universal-mac.zip
sha512: dW5p
releaseDate: '2026-11-08T00:00:00.000Z'
"""

@Test func feedPicksTheArm64ZipOverTheBridgeName() throws {
    let release = try UpdateFeed.parse(feed)
    #expect(release.version == "2.0.1")
    #expect(release.zip == ReleaseFile(url: "CatNotch-2.0.1-arm64-mac.zip", sha512: "YXJt"))
}

@Test func feedFallsBackToTheUniversalZipOfTheBridgeRelease() throws {
    let release = try UpdateFeed.parse("version: 2.0.0\nfiles:\n  - url: CatNotch-2.0.0-universal-mac.zip\n    sha512: dW5p\n")
    #expect(release.zip.url == "CatNotch-2.0.0-universal-mac.zip")
}

@Test func feedWithoutAVersionOrZipIsRejected() {
    #expect(throws: UpdateError.self) { try UpdateFeed.parse("files:\n  - url: a-mac.zip\n    sha512: x\n") }
    #expect(throws: UpdateError.self) { try UpdateFeed.parse("version: 2.0.1\nfiles:\n  - url: CatNotch.dmg\n    sha512: x\n") }
}

@Test func versionsCompareNumberByNumber() {
    #expect(UpdateFeed.isNewer("2.0.10", than: "2.0.9"))
    #expect(UpdateFeed.isNewer("2.1", than: "2.0.9"))
    #expect(!UpdateFeed.isNewer("2.0.0", than: "2.0.0"))
    #expect(!UpdateFeed.isNewer("1.9.9", than: "2.0.0"))
}

// MARK: - install, on temp folders

private func temp() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("catnotch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeApp(_ dir: URL, _ name: String, marker: String) throws -> URL {
    let app = dir.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    try marker.write(to: app.appendingPathComponent("Contents/marker"), atomically: true, encoding: .utf8)
    return app
}

private func marker(_ app: URL) throws -> String {
    try String(contentsOf: app.appendingPathComponent("Contents/marker"), encoding: .utf8)
}

/// Zips `app` the way a release does (`ditto -c -k --keepParent`) and returns the zip and its base64 sha512.
private func pack(_ app: URL, in dir: URL) throws -> (URL, String) {
    let zip = dir.appendingPathComponent("update.zip")
    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
    try ditto.run()
    ditto.waitUntilExit()
    return (zip, try UpdateInstall.sha512(of: zip))
}

@Test func installReplacesTheAppAndLeavesNothingBehind() throws {
    let dir = try temp()
    let installed = try makeApp(dir, "CatNotch.app", marker: "old")
    let fresh = try temp()
    let (zip, digest) = try pack(try makeApp(fresh, "CatNotch.app", marker: "new"), in: fresh)

    try UpdateInstall.install(zip: zip, sha512: digest, installed: installed)

    #expect(try marker(installed) == "new")
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["CatNotch.app"]) // no .old, no work folder
}

@Test func swapClearsTheQuarantineFlag() throws {
    let dir = try temp()
    let installed = try makeApp(dir, "CatNotch.app", marker: "old")
    let next = try makeApp(dir, "CatNotch-new.app", marker: "new")
    _ = try Process.output("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;0;x;", next.path])

    try UpdateInstall.swap(next: next, installed: installed)

    #expect(try marker(installed) == "new")
    #expect(!(try Process.output("/usr/bin/xattr", [installed.path])).contains("com.apple.quarantine"))
}

@Test func aZipThatFailsItsChecksumIsRejectedAndTheOldAppStays() throws {
    let dir = try temp()
    let installed = try makeApp(dir, "CatNotch.app", marker: "old")
    let fresh = try temp()
    let (zip, _) = try pack(try makeApp(fresh, "CatNotch.app", marker: "new"), in: fresh)

    #expect(throws: UpdateError.checksum) { try UpdateInstall.install(zip: zip, sha512: "wrong", installed: installed) }
    #expect(try marker(installed) == "old")
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["CatNotch.app"])
}

@Test func aZipWithoutTheAppFailsAndTheOldAppStays() throws {
    let dir = try temp()
    let installed = try makeApp(dir, "CatNotch.app", marker: "old")
    let fresh = try temp()
    let (zip, digest) = try pack(try makeApp(fresh, "Other.app", marker: "new"), in: fresh)

    #expect(throws: UpdateError.failed) { try UpdateInstall.install(zip: zip, sha512: digest, installed: installed) }
    #expect(try marker(installed) == "old")
}

@Test func swapPutsTheOldAppBackWhenTheMoveFails() throws {
    let dir = try temp()
    let installed = try makeApp(dir, "CatNotch.app", marker: "old")
    // The new app sits inside the old one, so it is gone once the old one is set aside and the move fails.
    let next = try makeApp(installed.appendingPathComponent("Contents"), "new.app", marker: "new")

    #expect(throws: UpdateError.failed) { try UpdateInstall.swap(next: next, installed: installed) }
    #expect(try marker(installed) == "old")
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["CatNotch.app"])
}

@Test func aReadOnlyFolderReportsUnwritableAndTouchesNothing() throws {
    let dir = try temp()
    let locked = dir.appendingPathComponent("locked")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    let installed = try makeApp(locked, "CatNotch.app", marker: "old")
    let next = try makeApp(dir, "CatNotch-new.app", marker: "new")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

    #expect(!UpdateInstall.writable(locked))
    #expect(throws: UpdateError.unwritable) { try UpdateInstall.swap(next: next, installed: installed) }
    #expect(try marker(installed) == "old")
    #expect(FileManager.default.fileExists(atPath: next.path))
}

private extension Process {
    static func output(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

@Test func installInAReadOnlyFolderReportsUnwritableBeforeLookingAtTheZip() throws {
    let dir = try temp()
    let locked = dir.appendingPathComponent("locked")
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    let installed = try makeApp(locked, "CatNotch.app", marker: "old")
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

    #expect(throws: UpdateError.unwritable) { try UpdateInstall.install(zip: dir.appendingPathComponent("none.zip"), sha512: "x", installed: installed) }
    #expect(try marker(installed) == "old")
}
