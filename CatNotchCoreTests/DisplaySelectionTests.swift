import Testing
@testable import CatNotchCore

@Test func settingParsing() {
    #expect(DisplaySelection(setting: "all") == .all)
    #expect(DisplaySelection(setting: "primary") == .primary)
    #expect(DisplaySelection(setting: "42") == .chosen(42))
    #expect(DisplaySelection(setting: nil) == .primary)
    #expect(DisplaySelection(setting: "junk") == .primary)
}

@Test func allGetsEveryDisplay() {
    #expect(DisplaySelection.all.targets(available: [1, 2, 3], primary: 1) == [1, 2, 3])
}

@Test func primaryGetsOnlyPrimary() {
    #expect(DisplaySelection.primary.targets(available: [1, 2], primary: 1) == [1])
}

@Test func chosenGetsThatDisplay() {
    #expect(DisplaySelection.chosen(2).targets(available: [1, 2], primary: 1) == [2])
}

@Test func unpluggedChosenFallsBackToPrimary() {
    #expect(DisplaySelection.chosen(9).targets(available: [1, 2], primary: 1) == [1])
}
