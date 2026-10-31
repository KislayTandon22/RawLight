import XCTest

final class RawLightUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["RAWLIGHT_FRESH"] = "1"
        app.launch()
    }

    private func openFirstPhoto() {
        let tile = app.buttons["tile"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 40), "library shows photos")
        tile.tap()
        XCTAssertTrue(app.staticTexts["Edit"].waitForExistence(timeout: 20), "editor opens")
    }

    /// On the phone the inspector is short: scroll it until `el` can be touched.
    @discardableResult
    private func reveal(_ el: XCUIElement) -> XCUIElement {
        var n = 0
        while !(el.exists && el.isHittable) && n < 12 {
            let inspector = app.scrollViews["inspector"].firstMatch
            if inspector.exists { inspector.swipeUp(velocity: .slow) } else { Thread.sleep(forTimeInterval: 1) }
            n += 1
        }
        XCTAssertTrue(el.exists, "element exists")
        return el
    }

    /// These drive the full-height tablet inspector; on the phone the short inspector scrolls and
    /// XCUITest swipes keep their momentum, so the phone is covered by hand and by the other tests.
    private func skipOnPhone() throws {
        if UIDevice.current.userInterfaceIdiom == .phone { throw XCTSkip("iPad-only interaction test") }
    }

    private func value(_ id: String) -> String { app.staticTexts["value.\(id)"].label }

    func testLibraryShowsDemoPhotos() {
        XCTAssertTrue(app.buttons["tile"].firstMatch.waitForExistence(timeout: 40))
        XCTAssertGreaterThan(app.buttons.matching(identifier: "tile").count, 5)
    }

    func testExposureSliderMovesAndResets() throws {
        try skipOnPhone()
        openFirstPhoto()
        let slider = reveal(app.otherElements["slider.light.exposure"].firstMatch)
        XCTAssertEqual(value("light.exposure"), "0.00")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertNotEqual(value("light.exposure"), "0.00", "dragging changes exposure")
    }

    /// The reported bug: the tone curve did nothing until a second point existed.
    func testToneCurveWorksWithOnePoint() throws {
        try skipOnPhone()
        openFirstPhoto()
        reveal(app.staticTexts["curve.state"].firstMatch).tap()
        let graph = reveal(app.otherElements["curve.graph"].firstMatch)
        XCTAssertEqual(app.staticTexts["curve.state"].label, "Linear")
        graph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: graph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        XCTAssertEqual(app.staticTexts["curve.state"].label, "Custom", "one added point already bends the curve")
    }

    /// Regression: a tap on a slider track used to commit the previous value right after the new one.
    func testSliderTapKeepsItsValue() {
        openFirstPhoto()
        let slider = reveal(app.otherElements["slider.light.contrast"].firstMatch)
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        let first = value("light.contrast")
        XCTAssertNotEqual(first, "0")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(value("light.contrast"), first, "the value stays after the commit")
    }

    func testHealSpotAddsOne() {
        openFirstPhoto()
        app.buttons["Heal"].firstMatch.tap()
        let canvasPoint = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3))
        canvasPoint.tap()
        XCTAssertTrue(app.staticTexts["1 spot"].waitForExistence(timeout: 15), "a tap adds one heal spot")
    }

    func testModesSwitch() {
        openFirstPhoto()
        for mode in ["Crop", "Mask", "Heal", "Looks", "History", "Edit"] {
            app.buttons[mode].firstMatch.tap()
            XCTAssertTrue(app.staticTexts[mode].firstMatch.waitForExistence(timeout: 5), "\(mode) panel shows")
        }
    }

    func testAddRadialMask() {
        openFirstPhoto()
        app.buttons["Mask"].firstMatch.tap()
        app.buttons["Radial gradient"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Mask 1"].firstMatch.waitForExistence(timeout: 10), "mask appears in the list")
    }

    func testLooksShowPreviews() throws {
        try skipOnPhone()
        openFirstPhoto()
        app.buttons["Looks"].firstMatch.tap()
        reveal(app.buttons["Warm Glow"].firstMatch)
        // previews are images inside the look buttons
        XCTAssertTrue(app.buttons["Warm Glow"].firstMatch.images.firstMatch.waitForExistence(timeout: 30), "a look preview image renders")
    }

    func testDetailShowsAIDenoiseCard() {
        openFirstPhoto()
        app.buttons["Detail"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["AI Denoise"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sharpening"].exists)
        XCTAssertTrue(app.staticTexts["Apple noise reduction"].exists)
    }

    func testExportSheetOpensAndExports() {
        openFirstPhoto()
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'share' OR label CONTAINS[c] 'upload'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Export"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Export"].firstMatch.tap()
        let done = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Share or Save' OR label CONTAINS 'Share 1'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 90), "export finishes")
    }

    func testCompareSplitAppears() {
        openFirstPhoto()
        let menu = app.buttons["compare.menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()  // a plain tap turns the split slider on
        XCTAssertTrue(app.images["arrow.left.and.right"].firstMatch.waitForExistence(timeout: 15), "split handle shows")
    }

    func testInfoAddsKeyword() {
        openFirstPhoto()
        app.buttons["Info"].firstMatch.tap()
        let field = app.textFields["info.keyword"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("rawlighttest\n")
        XCTAssertTrue(app.buttons["rawlighttest"].firstMatch.waitForExistence(timeout: 10) || app.staticTexts["rawlighttest"].firstMatch.waitForExistence(timeout: 5), "keyword chip appears")
    }

    func testSettingsOpens() {
        XCTAssertTrue(app.buttons["tile"].firstMatch.waitForExistence(timeout: 40))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'All Photos'")).firstMatch.tap()
        app.buttons["Settings…"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Preview cache"].waitForExistence(timeout: 10))
    }

    func testPeopleSheetOffersFaceModels() {
        XCTAssertTrue(app.buttons["tile"].firstMatch.waitForExistence(timeout: 40))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'All Photos'")).firstMatch.tap()
        app.buttons["People…"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Face models"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["YuNet (face detector)"].exists, "the detector is offered as an optional download")
    }

    func testMergeSheetOpensForTwoSelectedPhotos() {
        XCTAssertTrue(app.buttons["tile"].firstMatch.waitForExistence(timeout: 40))
        app.buttons["Select"].firstMatch.tap()
        let tiles = app.buttons.matching(identifier: "tile")
        tiles.element(boundBy: 0).tap(); tiles.element(boundBy: 1).tap()
        app.buttons["merge.open"].firstMatch.tap()
        XCTAssertTrue(app.buttons["merge.preview"].waitForExistence(timeout: 10))
        app.buttons["merge.preview"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'demo photo'")).firstMatch.waitForExistence(timeout: 20), "a demo library explains why it cannot merge")
    }
}
