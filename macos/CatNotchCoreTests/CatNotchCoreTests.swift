import Testing
@testable import CatNotchCore

@Test func bundleIDIsCatNotch() {
    #expect(CatNotchCore.bundleID == "com.devezio.catnotch")
}
