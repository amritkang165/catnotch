import Foundation
import Testing
@testable import CatNotchCore

// MARK: battery (ported from main/ipc/battery.test.ts)

@Test func batteryReadsADischargingLaptop() {
    let state = BatteryState(pmset: " -InternalBattery-0 (id=1)\t42%; discharging; 3:20 remaining present: true")
    #expect(state == BatteryState(level: 0.42, charging: false, supported: true))
}

@Test(arguments: ["charging", "AC attached", "finishing charge"])
func batteryCountsPowerAsCharging(status: String) {
    #expect(BatteryState(pmset: " -InternalBattery-0 (id=1)\t80%; \(status); 0:30 remaining").charging)
}

@Test func batteryIsUnsupportedWithNoBatteryLine() {
    #expect(!BatteryState(pmset: "Now drawing from 'AC Power'\n").supported)
    #expect(!BatteryState(pmset: "").supported)
}

@Test func batteryWarnsOnlyWhenLowAndNotCharging() {
    #expect(BatteryState(level: 0.2, charging: false, supported: true).isLow)
    #expect(!BatteryState(level: 0.2, charging: true, supported: true).isLow)
    #expect(!BatteryState(level: 0.21, charging: false, supported: true).isLow)
}

// MARK: headphones (from useHeadphones.ts)

@Test(arguments: [("Headphones (WH-1000XM4)", "WH-1000XM4"), ("AirPods Pro", "AirPods Pro"), ("Sam's Buds Hands-Free", "Sam's Buds Hands-Free")])
func headphoneNameIsTidied(label: String, name: String) {
    #expect(Headphones.name(of: label) == name)
}

@Test func headphoneNameDropsHandsFreeSuffixInsideBrackets() {
    #expect(Headphones.name(of: "Headset (WH-1000XM4 Hands-Free)") == "WH-1000XM4")
}

@Test func onlyWornOutputsCount() {
    #expect(Headphones.isWorn("AirPods Pro"))
    #expect(Headphones.isWorn("WF-1000XM5"))
    #expect(!Headphones.isWorn("MacBook Pro Speakers"))
    #expect(!Headphones.isWorn("LG UltraFine Display Audio"))
}

@Test func arrivalIsTheNewWornOutputOnly() {
    let before = ["speakers": "MacBook Pro Speakers"]
    // Already plugged in at launch is not news; a new speaker is not worn.
    #expect(Headphones.arrival(before: before, now: before) == nil)
    #expect(Headphones.arrival(before: before, now: before.merging(["tv": "Samsung TV"]) { $1 }) == nil)
    #expect(Headphones.arrival(before: before, now: before.merging(["a": "AirPods Pro"]) { $1 }) == "AirPods Pro")
}

// MARK: most used apps

@Test func topAppsAreRankedByLaunchCount() {
    let counts = ["/A/Mail.app": 3, "/A/Safari.app": 90, "/A/Never.app": 0, "/A/Notes.app": 12]
    #expect(TopApps.rank(counts, excluding: nil, limit: 2) == ["/A/Safari.app", "/A/Notes.app"])
}

@Test func topAppsLeaveOutNeverLaunchedAndSelf() {
    let counts = ["/A/Me.app": 99, "/A/Mail.app": 1, "/A/Never.app": 0]
    #expect(TopApps.rank(counts, excluding: "/A/Me.app", limit: 12) == ["/A/Mail.app"])
}

@Test func topAppsBreakTiesByPathSoTheOrderIsStable() {
    #expect(TopApps.rank(["/A/B.app": 5, "/A/A.app": 5], excluding: nil, limit: 2) == ["/A/A.app", "/A/B.app"])
}

@Test func mdlsOutputIsReadInTheOrderAsked() {
    #expect(TopApps.counts(paths: ["/a", "/b", "/c"], mdls: "4\u{0}0\u{0}x") == ["/a": 4, "/b": 0, "/c": 0])
    #expect(TopApps.counts(paths: ["/a", "/b"], mdls: "") == ["/a": 0, "/b": 0])
}

@Test func mdlsCountsSurviveAPathListedTwice() {
    #expect(TopApps.counts(paths: ["/a", "/a"], mdls: "4\u{0}2") == ["/a": 4])
}

// MARK: wifi

@Test func wifiSignalMovesInStepsOfTwenty() {
    #expect(Wifi.signal(rssi: -50) == 100)
    #expect(Wifi.signal(rssi: -60) == 80)
    #expect(Wifi.signal(rssi: -67) == 60) // a drifting reading is not news
    #expect(Wifi.signal(rssi: -100) == 0)
    #expect(Wifi.signal(rssi: -20) == 100)
}

// MARK: bluetooth

@Test func bluetoothListsConnectedDevicesWithTheirBattery() {
    let json = """
    {"SPBluetoothDataType":[{"device_connected":[
      {"AirPods Pro":{"device_batteryLevelLeft":"80%","device_batteryLevelRight":"65%"}},
      {"Magic Mouse":{"device_batteryLevelMain":"41%"}},
      {"Keyboard":{"device_address":"AA"}}
    ],"device_not_connected":[{"Old Speaker":{}}]}]}
    """
    #expect(BluetoothDevice.connected(profiler: Data(json.utf8)) == [
        BluetoothDevice(name: "AirPods Pro", battery: 65),
        BluetoothDevice(name: "Magic Mouse", battery: 41),
        BluetoothDevice(name: "Keyboard", battery: nil),
    ])
}

@Test func bluetoothIsEmptyForOutputItDoesNotKnow() {
    #expect(BluetoothDevice.connected(profiler: Data()).isEmpty)
    #expect(BluetoothDevice.connected(profiler: Data("{\"SPBluetoothDataType\":[{}]}".utf8)).isEmpty)
}
