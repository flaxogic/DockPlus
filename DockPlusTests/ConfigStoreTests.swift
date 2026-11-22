import XCTest
@testable import DockPlus

final class ConfigStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockPlusTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testFreshLoadReturnsStarterDock() {
        let store = ConfigStore(directoryURL: tempDir)
        let config = store.load()

        XCTAssertEqual(config.docks.count, 1)
        XCTAssertEqual(config.docks[0].name, "Dock 1")
    }

    func testRoundTripThreeNamedDocks() throws {
        let store = ConfigStore(directoryURL: tempDir)

        let coding = DockConfig(
            name: "Coding",
            items: [
                DockItem(kind: .app, path: "/Applications/Xcode.app"),
                DockItem.separator(),
                DockItem(kind: .folder, path: "/Users/alex/Desktop")
            ],
            orientation: .horizontal,
            placement: .snapped(edge: .bottom, offset: 12, displayUUID: "DISPLAY-1"),
            iconSize: 52,
            autoHide: true,
            isVisible: true,
            glassTransparency: 0.65,
            tintColor: DockConfig.TintColor(red: 0.2, green: 0.5, blue: 0.9)
        )
        let comms = DockConfig(
            name: "Comms",
            items: [DockItem(kind: .app, path: "/System/Applications/Mail.app")],
            orientation: .vertical,
            placement: .floating(x: 120, y: 340, displayUUID: nil),
            iconSize: 44,
            autoHide: false,
            isVisible: true
        )
        let design = DockConfig(
            name: "Design",
            items: [DockItem(kind: .file, path: "/tmp/mockup.png")],
            orientation: .vertical,
            placement: .snapped(edge: .right, offset: -20, displayUUID: "DISPLAY-2"),
            iconSize: 64,
            autoHide: false,
            isVisible: false
        )

        let original = AppConfig(
            docks: [coding, comms, design],
            startNewDocksFromCurrentDock: true,
            disableSystemDock: true,
            savedSystemDockPreferences: SystemDockPreferences(hadAutoHide: true, autoHide: false, autoHideDelay: 0.2)
        )
        try store.saveImmediately(original)
        let loaded = store.load()

        XCTAssertEqual(loaded, original)
        XCTAssertTrue(loaded.startNewDocksFromCurrentDock)
        XCTAssertTrue(loaded.disableSystemDock)
        XCTAssertEqual(loaded.savedSystemDockPreferences, original.savedSystemDockPreferences)
    }

    func testSystemDockReaderParsesPlist() throws {
        let plist: [String: Any] = [
            "persistent-apps": [
                ["tile-data": ["file-data": ["_CFURLString": "file:///System/Applications/Safari.app/"]]],
                ["tile-data": ["file-data": ["_CFURLString": "file:///System/Applications/Notes.app/"]]]
            ],
            "persistent-others": [
                ["tile-data": ["file-data": ["_CFURLString": "file:///Applications/"]]]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let items = SystemDockReader.parse(plistData: data)

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].path, "/System/Applications/Safari.app")
        XCTAssertEqual(items[1].path, "/System/Applications/Notes.app")
        XCTAssertEqual(items[2].kind, .folder)
    }

    func testCorruptPrimaryRecoversFromBackup() throws {
        let store = ConfigStore(directoryURL: tempDir)

        let first = AppConfig(docks: [DockConfig(name: "First")])
        let second = AppConfig(docks: [DockConfig(name: "Second")])

        try store.saveImmediately(first)
        try store.saveImmediately(second)

        try Data("{ invalid json !!!".utf8).write(to: store.configURL)

        let recovered = store.load()
        XCTAssertEqual(recovered.docks.count, 1)
        XCTAssertEqual(recovered.docks[0].name, "First")
    }

    func testCorruptPrimaryAndBackupFallsBackToStarterDock() throws {
        let store = ConfigStore(directoryURL: tempDir)
        try Data("not json".utf8).write(to: store.configURL)
        try Data("also not json".utf8).write(to: store.backupURL)

        let fallback = store.load()
        XCTAssertEqual(fallback.docks.count, 1)
        XCTAssertEqual(fallback.docks[0].name, "Dock 1")
    }
}
