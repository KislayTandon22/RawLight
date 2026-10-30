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

    private func value(_ id: String) -> String { app.staticTexts["value.\(id)"].label }

    func testLibraryShowsDemoPhotos() {
        XCTAssertTrue(app.buttons["tile"].firstMatch.waitForExistence(timeout: 40))
        XCTAssertGreaterThan(app.buttons.matching(identifier: "tile").count, 5)
    }

    func testExposureSliderMovesAndResets() {
        openFirstPhoto()
        let slider = app.otherElements["slider.light.exposure"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 20))
        XCTAssertEqual(value("light.exposure"), "0.00")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertNotEqual(value("light.exposure"), "0.00", "dragging changes exposure")
    }

    /// The reported bug: the tone curve did nothing until a second point existed.
    func testToneCurveWorksWithOnePoint() {
        openFirstPhoto()
        app.staticTexts["curve.state"].firstMatch.tap()
        let graph = app.otherElements["curve.graph"].firstMatch
        XCTAssertTrue(graph.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["curve.state"].label, "Linear")
        graph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: graph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        XCTAssertEqual(app.staticTexts["curve.state"].label, "Custom", "one added point already bends the curve")
    }

    /// Regression: a tap on a slider track used to commit the previous value right after the new one.
    func testSliderTapKeepsItsValue() {
        openFirstPhoto()
        let slider = app.otherElements["slider.light.contrast"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 20))
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        let first = value("light.contrast")
        XCTAssertNotEqual(first, "0")
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(value("light.contrast"), first, "the value stays after the commit")
    }

    func testHealSpotAddsOne() {
        openFirstPhoto()
        app.buttons["Heal"].firstMatch.tap()
        let canvasPoint = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45))
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
        app.buttons["Add mask"].firstMatch.tap()
        app.buttons["Radial gradient"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Mask 1"].firstMatch.waitForExistence(timeout: 10), "mask appears in the list")
    }

    func testLooksShowPreviews() {
        openFirstPhoto()
        app.buttons["Looks"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Warm Glow"].firstMatch.waitForExistence(timeout: 20))
        // previews are images inside the look buttons
        XCTAssertTrue(app.buttons["Warm Glow"].firstMatch.images.firstMatch.waitForExistence(timeout: 30), "a look preview image renders")
    }

    func testDetailShowsAIDenoiseCard() {
        openFirstPhoto()
        app.buttons["Detail"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["AI Denoise"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sharpening"].exists)
    }

    func testExportSheetOpensAndExports() {
        openFirstPhoto()
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'share' OR label CONTAINS[c] 'upload'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Export"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Export"].firstMatch.tap()
        let done = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Share or Save' OR label CONTAINS 'Share 1'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 90), "export finishes")
    }
}
