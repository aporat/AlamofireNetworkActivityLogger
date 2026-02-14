import Testing
import Foundation
@testable import AlamofireNetworkActivityLogger

// MARK: - LoggerLevel Tests

@Suite("LoggerLevel")
struct LoggerLevelTests {

    @Test("off disables logging")
    func offDisablesLogging() {
        #expect(LoggerLevel.off.isLoggingEnabled == false)
    }

    @Test("fatal disables logging")
    func fatalDisablesLogging() {
        #expect(LoggerLevel.fatal.isLoggingEnabled == false)
    }

    @Test("debug enables logging")
    func debugEnablesLogging() {
        #expect(LoggerLevel.debug.isLoggingEnabled == true)
    }

    @Test("info enables logging")
    func infoEnablesLogging() {
        #expect(LoggerLevel.info.isLoggingEnabled == true)
    }
}

// MARK: - AlamofireNetworkLogger Actor Tests

@Suite("AlamofireNetworkLogger")
struct AlamofireNetworkLoggerTests {

    // MARK: Default State

    @Test("shared instance is initialized with debug level")
    func defaultLevelIsDebug() async {
        let logger = AlamofireNetworkLogger()
        let level = await logger.level
        #expect(level == .debug)
    }
    
    // MARK: Level Mutation

    @Test("level can be changed to info")
    func canSetLevelToInfo() async {
        let logger = AlamofireNetworkLogger()
        await logger.setLevel(.info)
        let level = await logger.level
        #expect(level == .info)
    }

    @Test("level can be changed to off")
    func canSetLevelToOff() async {
        let logger = AlamofireNetworkLogger()
        await logger.setLevel(.off)
        let level = await logger.level
        #expect(level == .off)
    }

    // MARK: Start / Stop Logging

    @Test("startLogging does not throw")
    func startLoggingDoesNotThrow() async {
        let logger = AlamofireNetworkLogger()
        await logger.startLogging()
        // If we reach here without crashing, the actor started safely.
    }

    @Test("calling startLogging twice is safe")
    func startLoggingIsIdempotent() async {
        let logger = AlamofireNetworkLogger()
        await logger.startLogging()
        await logger.startLogging()
        // Second call should be a no-op; no crash expected.
    }

    @Test("stopLogging after startLogging is safe")
    func stopLoggingAfterStart() async {
        let logger = AlamofireNetworkLogger()
        await logger.startLogging()
        await logger.stopLogging()
    }

    @Test("stopLogging without prior startLogging is safe")
    func stopLoggingWithoutStart() async {
        let logger = AlamofireNetworkLogger()
        await logger.stopLogging()
        // Should not crash or hang.
    }
}

// MARK: - LoggerLevel Sendability

@Suite("LoggerLevel Sendability")
struct LoggerLevelSendabilityTests {

    @Test("LoggerLevel values can cross concurrency boundaries")
    func sendableAcrossTasks() async {
        let level: LoggerLevel = .debug
        let result = await Task.detached {
            level
        }.value
        #expect(result == .debug)
    }
}
