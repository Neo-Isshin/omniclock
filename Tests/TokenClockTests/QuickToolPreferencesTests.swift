#if os(macOS)
import XCTest
@testable import TokenClock

@MainActor final class QuickToolPreferencesTests: XCTestCase {
    func testDragAndArrowOrderSurviveRelaunchWithoutEnablingHiddenTools() {
        let name="QuickOrderTests."+UUID().uuidString,store=UserDefaults(suiteName:name)!
        defer {store.removePersistentDomain(forName:name)}
        let prefs=QuickToolPreferences(defaults:store)
        prefs.toggle(.local)
        prefs.move(.notebook,to:.network)
        XCTAssertEqual(prefs.order.first,.notebook)
        prefs.move(.quota,by:-1)
        let saved=prefs.order
        prefs.move(.share,to:.model)
        XCTAssertEqual(prefs.order,saved)
        XCTAssertFalse(prefs.order.contains(.local))
        XCTAssertEqual(QuickToolPreferences(defaults:store).order,saved)
    }
    func testNetworkLeadsDefaultsButCustomOrdersAndHiddenToolsStayUntouched() {
        let name="QuickNetworkTests."+UUID().uuidString,store=UserDefaults(suiteName:name)!
        defer {store.removePersistentDomain(forName:name)}
        XCTAssertEqual(QuickToolPreferences(defaults:store).order.first,.network)
        store.set(["model","network","local","quota","history","notebook"],forKey:"toolbox.quickOrder")
        store.set(1,forKey:"toolbox.quickOrderVersion")
        let migrated=QuickToolPreferences(defaults:store)
        XCTAssertEqual(migrated.order.first,.network)
        migrated.order=[.notebook,.model,.quota]
        XCTAssertEqual(QuickToolPreferences(defaults:store).order,[.notebook,.model,.quota])
        store.set(["model","local","network"],forKey:"toolbox.quickOrder");store.set(1,forKey:"toolbox.quickOrderVersion")
        XCTAssertEqual(QuickToolPreferences(defaults:store).order,[.model,.local,.network])
    }
    func testOldDefaultMigrationRunsOnceAndDoesNotUndoLaterVisibilityChoices() {
        let name="QuickMigrationTests."+UUID().uuidString,store=UserDefaults(suiteName:name)!
        defer {store.removePersistentDomain(forName:name)}
        store.set(["model","network","local","quota"],forKey:"toolbox.quickOrder")
        let prefs=QuickToolPreferences(defaults:store)
        XCTAssertEqual(prefs.order,QuickToolPreferences.defaults)
        prefs.toggle(.history);prefs.toggle(.notebook)
        XCTAssertEqual(prefs.order,[.network,.model,.local,.quota])
        XCTAssertEqual(QuickToolPreferences(defaults:store).order,[.network,.model,.local,.quota])
        prefs.order=[]
        XCTAssertTrue(QuickToolPreferences(defaults:store).order.isEmpty)
    }
}
#endif
