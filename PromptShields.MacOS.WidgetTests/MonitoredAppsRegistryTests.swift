import XCTest
@testable import PromptShields_MacOS_Widget

/// Tests for `MonitoredAppsRegistry` (PS-13).
///
/// The registry is a singleton that loads from `Resources/MonitoredApps.plist`
/// at init. These tests verify:
/// - Plist loading produces the expected canonical apps.
/// - Browser detection is config-driven.
/// - Per-app enable/disable round-trips through UserDefaults.
/// - `isDisabled(bundleId:)` returns false for unknown apps even when some
///   apps are disabled (the gate must not accidentally block non-listed apps).
final class MonitoredAppsRegistryTests: XCTestCase {

    private let disabledKey = "ai.bit-pulse.promptshields.disabledMonitoredApps"

    override func setUp() {
        super.setUp()
        // Start each test from a clean per-user state — no apps disabled.
        UserDefaults.standard.removeObject(forKey: disabledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: disabledKey)
        super.tearDown()
    }

    // MARK: - Catalog contents

    func testCatalogLoadsCanonicalApps() throws {
        let registry = MonitoredAppsRegistry.shared

        let ids = Set(registry.apps.map(\.id))
        XCTAssertTrue(ids.contains("chatgpt"), "ChatGPT must ship in the default catalog")
        XCTAssertTrue(ids.contains("claude"))
        XCTAssertTrue(ids.contains("notion"))
        XCTAssertTrue(ids.contains("copilot"))
        XCTAssertGreaterThanOrEqual(registry.apps.count, 5, "At least the 5 launch AI apps must be present")
    }

    func testCatalogPopulatesBothMatchers() {
        let registry = MonitoredAppsRegistry.shared
        guard let chatgpt = registry.apps.first(where: { $0.id == "chatgpt" }) else {
            return XCTFail("Expected ChatGPT entry in catalog")
        }
        XCTAssertTrue(chatgpt.bundleIds.contains("com.openai.chat"),
                      "ChatGPT must match the native Electron app bundle id")
        XCTAssertTrue(chatgpt.webHosts.contains { $0.contains("chat.openai.com") },
                      "ChatGPT must match the current web host")
        XCTAssertEqual(chatgpt.category, .mixed,
                       "ChatGPT ships as both a native app and a web tab")
    }

    // MARK: - Browser allowlist

    func testBrowserAllowlist() {
        let registry = MonitoredAppsRegistry.shared
        XCTAssertTrue(registry.isBrowser(bundleId: "com.google.Chrome"))
        XCTAssertTrue(registry.isBrowser(bundleId: "com.apple.Safari"))
        XCTAssertFalse(registry.isBrowser(bundleId: "com.apple.TextEdit"))
        XCTAssertFalse(registry.isBrowser(bundleId: ""))
    }

    // MARK: - Per-user enable / disable

    func testDefaultStateIsAllEnabled() {
        let registry = MonitoredAppsRegistry.shared
        for app in registry.apps {
            XCTAssertTrue(registry.isEnabled(app), "Apps default to enabled (opt-out model)")
        }
    }

    func testSetEnabledPersistsInUserDefaults() throws {
        let registry = MonitoredAppsRegistry.shared
        guard let chatgpt = registry.apps.first(where: { $0.id == "chatgpt" }) else {
            return XCTFail("ChatGPT missing from catalog")
        }

        registry.setEnabled(chatgpt, enabled: false)
        XCTAssertFalse(registry.isEnabled(chatgpt))

        let disabled = UserDefaults.standard.stringArray(forKey: disabledKey) ?? []
        XCTAssertTrue(disabled.contains("chatgpt"),
                      "Disabling must persist under the expected key")

        registry.setEnabled(chatgpt, enabled: true)
        XCTAssertTrue(registry.isEnabled(chatgpt))
        let afterReEnable = UserDefaults.standard.stringArray(forKey: disabledKey) ?? []
        XCTAssertFalse(afterReEnable.contains("chatgpt"),
                       "Re-enabling must remove the id from the disabled list")
    }

    // MARK: - Gate query

    func testIsDisabledRespectsPerAppToggle() throws {
        let registry = MonitoredAppsRegistry.shared
        guard let chatgpt = registry.apps.first(where: { $0.id == "chatgpt" }) else {
            return XCTFail("ChatGPT missing from catalog")
        }
        registry.setEnabled(chatgpt, enabled: false)

        XCTAssertTrue(registry.isDisabled(bundleId: "com.openai.chat"),
                      "Disabling ChatGPT must gate its native bundle")
        XCTAssertFalse(registry.isDisabled(bundleId: "com.apple.TextEdit"),
                       "Unlisted apps must NOT be gated — only explicit MonitoredApp disables block.")
        XCTAssertFalse(registry.isDisabled(bundleId: ""),
                       "Empty bundleId must not false-positive")
    }

    func testEnabledNativeAppReturnsNilWhenDisabled() throws {
        let registry = MonitoredAppsRegistry.shared
        guard let claude = registry.apps.first(where: { $0.id == "claude" }) else {
            return XCTFail("Claude missing from catalog")
        }

        XCTAssertNotNil(registry.enabledNativeApp(bundleId: "com.anthropic.claudefordesktop"))
        registry.setEnabled(claude, enabled: false)
        XCTAssertNil(registry.enabledNativeApp(bundleId: "com.anthropic.claudefordesktop"),
                     "Disabled native app must not resolve via enabledNativeApp")
    }

    func testEnabledWebAppMatchesHostSubstring() {
        let registry = MonitoredAppsRegistry.shared
        XCTAssertEqual(registry.enabledWebApp(urlString: "https://chat.openai.com/c/abc")?.id, "chatgpt")
        XCTAssertEqual(registry.enabledWebApp(urlString: "https://claude.ai/new")?.id, "claude")
        XCTAssertNil(registry.enabledWebApp(urlString: "https://example.com"),
                     "Unknown hosts must not match")
    }
}
