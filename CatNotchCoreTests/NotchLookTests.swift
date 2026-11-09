import Foundation
import Testing
@testable import CatNotchCore

private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
private func launch() -> CatNotchStore {
    CatNotchStore(directory: root.appendingPathComponent("CatNotch"), legacyDirectory: root.appendingPathComponent("DeskNotch"))
}

@Test func styleReadsOldNamesAndDefaultsToBlack() {
    #expect(NotchStyle(setting: "glass") == .glass)
    #expect(NotchStyle(setting: "transparent") == .transparent)
    #expect(NotchStyle(setting: "translucent") == .glass) // the old Electron name
    #expect(NotchStyle(setting: "mica") == .black)
    #expect(NotchStyle(setting: nil) == .black)
    #expect(NotchStyle(setting: "nonsense") == .black)
}

@Test func flavorDefaultsToMocha() {
    #expect(Flavor(setting: "frappe") == .frappe)
    #expect(Flavor(setting: "macchiato") == .macchiato)
    #expect(Flavor(setting: nil) == .mocha)
    #expect(Flavor(setting: "nonsense") == .mocha)
}

@Test func styleAndFlavorPersistUnderTheElectronKeys() {
    let s = launch()
    s.update { $0.notchStyle = .glass; $0.notchFlavor = .frappe }
    #expect(s.data.settings["notchStyle"] == .string("glass"))
    #expect(s.data.settings["notchFlavor"] == .string("frappe"))
    let reloaded = launch()
    #expect(reloaded.data.notchStyle == .glass)
    #expect(reloaded.data.notchFlavor == .frappe)
}

@Test func clockIsTwelveHour() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    func at(_ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: h, minute: m))! }
    #expect(WallClock.text(at(0, 5), calendar: cal) == WallClock.Text(time: "12:05", meridiem: "AM"))
    #expect(WallClock.text(at(9, 30), calendar: cal) == WallClock.Text(time: "9:30", meridiem: "AM"))
    #expect(WallClock.text(at(12, 0), calendar: cal) == WallClock.Text(time: "12:00", meridiem: "PM"))
    #expect(WallClock.text(at(23, 59), calendar: cal) == WallClock.Text(time: "11:59", meridiem: "PM"))
}

@Test func pagesHaveLabelsAndSymbols() {
    #expect(NotchPage.allCases.map(\.rawValue) == ["home", "desk", "calendar", "reminders", "files", "claude"])
    #expect(NotchPage.allCases.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty })
}

@Test func colourChoicesPersistUnderTheElectronKeys() {
    let s = launch()
    #expect(s.data.notchTint == NotchTint()) // nothing saved: the flavour's own look
    s.update { $0.notchColor = 0x112233; $0.notchAccent = 0xa6e3a1; $0.notchOpacity = 0.5; $0.catAccent = "Peach" }
    #expect(s.data.settings["notchColor"] == .string("#112233"))
    #expect(s.data.settings["notchAccent"] == .string("#a6e3a1"))
    #expect(s.data.settings["notchOpacity"] == .number(0.5))
    let reloaded = launch()
    #expect(reloaded.data.notchTint == NotchTint(fill: 0x112233, rim: 0xa6e3a1, opacity: 0.5))
    #expect(reloaded.data.catAccent == "Peach")
    s.update { $0.notchColor = nil }
    #expect(s.data.settings["notchColor"] == nil)
}

@Test func catCoatUsesTheFlavoursAccentByName() {
    #expect(Flavor.frappe.accent(named: "Peach") == 0xef9f76)
    #expect(Flavor.mocha.accent(named: "nonsense") == Flavor.mocha.mauve)
    let look = CompanionLook(character: .catppuccin, flavor: .mocha, coat: Flavor.mocha.accent(named: "Red"))
    #expect(look.ink == Flavor.mocha.red && look.bow == Flavor.mocha.pink) // the bow steps aside for a red coat
}
