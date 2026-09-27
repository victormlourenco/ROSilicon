import Testing
@testable import ROSilicon

@Suite("Log panel window layout")
struct LogPanelLayoutTests {
    @Test func itsSteadyStateValuesAreMinimums() {
        #expect(LogPanelLayout.minimumHeight(showingLog: false) == 432)
        #expect(LogPanelLayout.minimumHeight(showingLog: true) == 617)
    }

    @Test func openingAddsOnlyTheLogsHeight() {
        #expect(LogPanelLayout.targetHeight(currentHeight: 432, showingLog: true) == 617)
        #expect(LogPanelLayout.targetHeight(currentHeight: 700, showingLog: true) == 885)
    }

    @Test func closingRestoresTheHeightFromBeforeOpening() {
        #expect(LogPanelLayout.targetHeight(currentHeight: 617, showingLog: false) == 432)
        #expect(LogPanelLayout.targetHeight(currentHeight: 885, showingLog: false) == 700)
    }

    @Test func aMissingMeasurementFallsBackToTheNewMinimum() {
        #expect(LogPanelLayout.targetHeight(currentHeight: 0, showingLog: false) == 432)
        #expect(LogPanelLayout.targetHeight(currentHeight: 0, showingLog: true) == 617)
    }
}
