import Alamofire
import Foundation
import Testing
@testable import AlamofireNetworkActivityLogger

// MARK: - Fixtures

private func makeRequest(
    _ method: String = "GET",
    url: String = "https://api.example.com/users",
    headers: [String: String] = [:],
    body: Data? = nil
) -> URLRequest {
    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = method
    request.httpBody = body
    for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
    }
    return request
}

private func makeSnapshot(
    kind: RequestSnapshot.Kind = .data,
    request: URLRequest = makeRequest(),
    statusCode: Int? = 200,
    elapsedTime: Double = 0.25,
    error: (any Error)? = nil,
    isCancelled: Bool = false,
    responseHeaders: [String: String] = ["Content-Type": "application/json"],
    data: Data? = nil,
    downloadedFileURL: URL? = nil
) -> RequestSnapshot {
    RequestSnapshot(
        kind: kind,
        request: request,
        httpMethod: request.httpMethod ?? "GET",
        requestURL: request.url!,
        statusCode: statusCode,
        elapsedTime: elapsedTime,
        error: error,
        isCancelled: isCancelled,
        responseHeaders: responseHeaders,
        data: data,
        downloadedFileURL: downloadedFileURL
    )
}

private struct FakeError: LocalizedError {
    var errorDescription: String? { "something broke" }
}

private func render(_ snapshot: RequestSnapshot, level: LoggerLevel = .debug, maxBodyLength: Int? = nil, redacted: Set<String> = []) -> String {
    LogFormatter.render(snapshot, level: level, maxBodyLength: maxBodyLength, redactedHeaders: redacted)
}

/// Thread-safe collector for the logger's output sink.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) {
        lock.lock(); defer { lock.unlock() }
        entries.append(entry)
    }

    var all: [String] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    func first(where predicate: @escaping (String) -> Bool, timeout: Duration = .seconds(5)) async throws -> String? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let hit = all.first(where: predicate) { return hit }
            try await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }
}

// MARK: - LoggerLevel

@Suite("LoggerLevel")
struct LoggerLevelTests {
    @Test("off disables logging, debug and info enable it")
    func enablement() {
        #expect(LoggerLevel.off.isLoggingEnabled == false)
        #expect(LoggerLevel.debug.isLoggingEnabled == true)
        #expect(LoggerLevel.info.isLoggingEnabled == true)
    }
}

// MARK: - cURL generation

@Suite("cURL generation")
struct CURLTests {
    @Test("GET has no -X flag and quotes the URL with single quotes")
    func getRequest() {
        let curl = LogFormatter.cURLCommand(for: makeRequest(), redactedHeaders: [])
        #expect(curl == "curl -v 'https://api.example.com/users'")
    }

    @Test("POST includes -X, sorted headers and an escaped body")
    func postRequest() {
        let request = makeRequest(
            "POST",
            headers: ["Content-Type": "application/json", "Accept": "application/json"],
            body: Data(#"{"name":"O'Brien"}"#.utf8)
        )
        let curl = LogFormatter.cURLCommand(for: request, redactedHeaders: [])
        #expect(curl == #"curl -v -X POST -H 'Accept: application/json' -H 'Content-Type: application/json' -d '{"name":"O'\''Brien"}' 'https://api.example.com/users'"#)
    }

    @Test("redacted headers are masked case-insensitively")
    func redaction() {
        let request = makeRequest(headers: ["Authorization": "Bearer secret", "X-Trace": "abc"])
        let curl = LogFormatter.cURLCommand(for: request, redactedHeaders: ["authorization"])
        #expect(curl.contains("-H 'Authorization: <redacted>'"))
        #expect(curl.contains("-H 'X-Trace: abc'"))
        #expect(!curl.contains("secret"))
    }

    @Test("binary body becomes a shell comment, not broken syntax")
    func binaryBody() {
        let request = makeRequest("POST", body: Data([0xFF, 0xFE, 0x00, 0x01]))
        let curl = LogFormatter.cURLCommand(for: request, redactedHeaders: [])
        let lines = curl.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "curl -v -X POST 'https://api.example.com/users'")
        #expect(lines[1] == "# request body omitted: binary data (4 bytes)")
    }

    @Test("streamed body is called out")
    func streamedBody() {
        var request = makeRequest("POST")
        request.httpBodyStream = InputStream(data: Data("field=value".utf8))
        let curl = LogFormatter.cURLCommand(for: request, redactedHeaders: [])
        #expect(curl.hasSuffix("# request body omitted: streamed body (e.g. multipart upload)"))
    }

    @Test("URL containing a single quote is escaped")
    func quoteInURL() {
        let request = makeRequest(url: "https://api.example.com/q?x='y'")
        let curl = LogFormatter.cURLCommand(for: request, redactedHeaders: [])
        #expect(curl.hasSuffix(#"'https://api.example.com/q?x='\''y'\'''"#))
    }
}

// MARK: - Rendering

@Suite("Rendering")
struct RenderingTests {
    @Test("successful request renders request, response and body")
    func success() {
        let text = render(makeSnapshot(data: Data(#"{"b":1,"a":"x/y"}"#.utf8)))
        #expect(text.hasPrefix(LogFormatter.divider + "\n"))
        #expect(text.hasSuffix("\n" + LogFormatter.divider))
        #expect(text.contains("✅ [REQUEST] GET 'https://api.example.com/users'"))
        #expect(text.contains("cURL:\ncurl -v 'https://api.example.com/users'"))
        #expect(text.contains("✅ [RESPONSE] 200 [0.250s]"))
        #expect(text.contains("Headers: [\n  Content-Type: application/json\n]"))
        #expect(text.contains("Body:\n{\n  \"a\" : \"x/y\",\n  \"b\" : 1\n}"))
    }

    @Test("a 2xx with an error is not a success")
    func errorOverridesStatus() {
        let text = render(makeSnapshot(statusCode: 200, error: FakeError()))
        #expect(text.contains("❌ [REQUEST]"))
        #expect(text.contains("❌ [RESPONSE] 200"))
        #expect(text.contains("⚠️ Error: something broke"))
    }

    @Test("missing response prints none instead of 0")
    func noResponse() {
        let text = render(makeSnapshot(statusCode: nil, error: URLError(.notConnectedToInternet), responseHeaders: [:]))
        #expect(text.contains("❌ [RESPONSE] none"))
        #expect(!text.contains("[RESPONSE] 0"))
        #expect(!text.contains("Headers:"))
    }

    @Test("info level omits cURL, headers and body")
    func infoLevel() {
        let text = render(makeSnapshot(data: Data("hello".utf8)), level: .info)
        #expect(text.contains("✅ GET 'https://api.example.com/users'"))
        #expect(text.contains("✅ [RESPONSE] 200"))
        #expect(!text.contains("cURL"))
        #expect(!text.contains("Headers"))
        #expect(!text.contains("Body"))
    }

    @Test("response headers honor redaction")
    func responseHeaderRedaction() {
        let text = render(makeSnapshot(responseHeaders: ["Set-Cookie": "session=abc"]), redacted: ["set-cookie"])
        #expect(text.contains("  Set-Cookie: <redacted>"))
        #expect(!text.contains("session=abc"))
    }

    @Test("download renders the file path instead of a body")
    func download() {
        let fileURL = URL(fileURLWithPath: "/tmp/file.bin")
        let text = render(makeSnapshot(kind: .download, responseHeaders: [:], downloadedFileURL: fileURL))
        #expect(text.contains("Downloaded to: /tmp/file.bin"))
        #expect(!text.contains("Body:"))
    }
}

// MARK: - Body rendering

@Suite("Body rendering")
struct BodyRenderingTests {
    @Test("JSON is pretty printed with sorted keys")
    func json() {
        let body = LogFormatter.renderBody(Data(#"{"z":[1,2],"a":null}"#.utf8), contentType: "application/json; charset=utf-8", maxBodyLength: nil)
        #expect(body == "{\n  \"a\" : null,\n  \"z\" : [\n    1,\n    2\n  ]\n}")
    }

    @Test("invalid JSON under a JSON content type falls back to raw text")
    func invalidJSON() {
        let body = LogFormatter.renderBody(Data("not json".utf8), contentType: "application/json", maxBodyLength: nil)
        #expect(body == "not json")
    }

    @Test("long bodies are truncated with a marker")
    func truncation() {
        let text = String(repeating: "x", count: 100)
        let body = LogFormatter.renderBody(Data(text.utf8), contentType: "text/plain", maxBodyLength: 10)
        #expect(body == "xxxxxxxxxx\n… [truncated 90 characters]")
    }

    @Test("bodies at or under the limit are untouched")
    func noTruncation() {
        let body = LogFormatter.renderBody(Data("short".utf8), contentType: "text/plain", maxBodyLength: 5)
        #expect(body == "short")
    }

    @Test("non-textual content types are summarized")
    func binaryContentType() {
        let body = LogFormatter.renderBody(Data("GIF89a".utf8), contentType: "image/gif", maxBodyLength: nil)
        #expect(body == "Binary data (6 bytes)")
    }

    @Test("unknown content type that is not UTF-8 is summarized")
    func undecodable() {
        let body = LogFormatter.renderBody(Data([0xFF, 0xFE]), contentType: nil, maxBodyLength: nil)
        #expect(body == "Binary data (2 bytes)")
    }

    @Test("unknown content type that is UTF-8 is printed")
    func unknownButText() {
        let body = LogFormatter.renderBody(Data("plain".utf8), contentType: nil, maxBodyLength: nil)
        #expect(body == "plain")
    }
}

// MARK: - Actor behaviour

@Suite("AlamofireNetworkLogger")
struct AlamofireNetworkLoggerTests {
    @Test("defaults")
    func defaults() async {
        let logger = AlamofireNetworkLogger()
        #expect(await logger.level == .debug)
        #expect(await logger.maxBodyLength == 10_240)
        #expect(await logger.redactedHeaders.isEmpty)
        #expect(await logger.logsCancelledRequests == false)
    }

    @Test("setters update state")
    func setters() async {
        let logger = AlamofireNetworkLogger()
        await logger.setLevel(.info)
        await logger.setMaxBodyLength(nil)
        await logger.setRedactedHeaders(["Authorization"])
        await logger.setLogsCancelledRequests(true)
        #expect(await logger.level == .info)
        #expect(await logger.maxBodyLength == nil)
        #expect(await logger.redactedHeaders == ["Authorization"])
        #expect(await logger.logsCancelledRequests == true)
    }

    @Test("handle emits exactly one entry through the sink")
    func emitsOneEntry() async {
        let logger = AlamofireNetworkLogger()
        let collector = OutputCollector()
        await logger.setOutput { collector.append($0) }
        await logger.handle(makeSnapshot())
        #expect(collector.all.count == 1)
        #expect(collector.all.first?.contains("[RESPONSE] 200") == true)
    }

    @Test("level off suppresses output")
    func offSuppresses() async {
        let logger = AlamofireNetworkLogger()
        let collector = OutputCollector()
        await logger.setOutput { collector.append($0) }
        await logger.setLevel(.off)
        await logger.handle(makeSnapshot())
        #expect(collector.all.isEmpty)
    }

    @Test("cancelled requests are skipped unless opted in")
    func cancelled() async {
        let logger = AlamofireNetworkLogger()
        let collector = OutputCollector()
        await logger.setOutput { collector.append($0) }
        let snapshot = makeSnapshot(statusCode: nil, error: AFError.explicitlyCancelled, isCancelled: true)

        await logger.handle(snapshot)
        #expect(collector.all.isEmpty)

        await logger.setLogsCancelledRequests(true)
        await logger.handle(snapshot)
        #expect(collector.all.count == 1)
    }

    @Test("shouldSkip filters matching requests")
    func shouldSkip() async {
        let logger = AlamofireNetworkLogger()
        let collector = OutputCollector()
        await logger.setOutput { collector.append($0) }
        await logger.setShouldSkip { $0.url?.path.contains("analytics") == true }

        await logger.handle(makeSnapshot(request: makeRequest(url: "https://api.example.com/analytics/event")))
        await logger.handle(makeSnapshot(request: makeRequest(url: "https://api.example.com/users")))

        #expect(collector.all.count == 1)
        #expect(collector.all.first?.contains("/users") == true)
    }

    @Test("actor options flow into the rendered entry")
    func optionsApplied() async {
        let logger = AlamofireNetworkLogger()
        let collector = OutputCollector()
        await logger.setOutput { collector.append($0) }
        await logger.setRedactedHeaders(["Authorization"])
        await logger.setMaxBodyLength(4)

        let request = makeRequest(headers: ["Authorization": "Bearer secret"])
        await logger.handle(makeSnapshot(request: request, responseHeaders: ["Content-Type": "text/plain"], data: Data("0123456789".utf8)))

        let entry = collector.all.first ?? ""
        #expect(entry.contains("Authorization: <redacted>"))
        #expect(!entry.contains("secret"))
        #expect(entry.contains("0123\n… [truncated 6 characters]"))
    }

    @Test("start and stop are idempotent")
    func startStop() async {
        let logger = AlamofireNetworkLogger()
        await logger.startLogging()
        await logger.startLogging()
        await logger.stopLogging()
        await logger.stopLogging()
    }
}

// MARK: - End to end through Alamofire

/// Serves canned responses so the tests never touch the network.
private final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, headers, body): (Int, [String: String], Data)
        switch url.path {
        case "/json":
            (status, headers, body) = (200, ["Content-Type": "application/json"], Data(#"{"ok":true}"#.utf8))
        case "/file":
            (status, headers, body) = (200, ["Content-Type": "application/octet-stream"], Data([0x00, 0x01, 0x02]))
        default:
            (status, headers, body) = (500, ["Content-Type": "text/plain"], Data("boom".utf8))
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func makeStubSession() -> Session {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return Session(configuration: configuration)
}

@Suite("End to end", .serialized)
struct EndToEndTests {
    private func startLogger() async throws -> (AlamofireNetworkLogger, OutputCollector) {
        let logger = AlamofireNetworkLogger()
        let collector = OutputCollector()
        await logger.setOutput { collector.append($0) }
        await logger.startLogging()
        // Give the observation task a moment to subscribe before firing requests.
        try await Task.sleep(for: .milliseconds(100))
        return (logger, collector)
    }

    @Test("a completed data request is logged with request headers and body")
    func dataRequest() async throws {
        let (logger, collector) = try await startLogger()
        defer { Task { await logger.stopLogging() } }

        let session = makeStubSession()
        let url = "https://stub.example/json"
        _ = await session.request(
            url,
            method: .post,
            parameters: ["q": "1"],
            encoding: JSONEncoding.default,
            headers: ["X-Test": "1"]
        ).serializingData().response

        let entry = try #require(await collector.first { $0.contains(url) })
        #expect(entry.contains("✅ [REQUEST] POST '\(url)'"))
        #expect(entry.contains("-X POST"))
        #expect(entry.contains("-H 'Content-Type: application/json'"), "headers added by the encoder should appear in the cURL")
        #expect(entry.contains("-H 'X-Test: 1'"))
        #expect(entry.contains(#"-d '{"q":"1"}'"#))
        #expect(entry.contains("✅ [RESPONSE] 200"))
        #expect(entry.contains("Body:\n{\n  \"ok\" : true\n}"))
    }

    @Test("a failed request is marked as failed")
    func failedRequest() async throws {
        let (logger, collector) = try await startLogger()
        defer { Task { await logger.stopLogging() } }

        let session = makeStubSession()
        let url = "https://stub.example/error"
        _ = await session.request(url).validate().serializingData().response

        let entry = try #require(await collector.first { $0.contains(url) })
        #expect(entry.contains("❌ [RESPONSE] 500"))
        #expect(entry.contains("⚠️ Error:"))
        #expect(entry.contains("Body:\nboom"))
    }

    @Test("a download request logs its destination")
    func downloadRequest() async throws {
        let (logger, collector) = try await startLogger()
        defer { Task { await logger.stopLogging() } }

        let session = makeStubSession()
        let url = "https://stub.example/file"
        _ = await session.download(url).serializingDownloadedFileURL().response

        let entry = try #require(await collector.first { $0.contains(url) })
        #expect(entry.contains("✅ [RESPONSE] 200"))
        #expect(entry.contains("Downloaded to: "))
        #expect(!entry.contains("Body:"))
    }

    @Test("cancelled requests are not logged by default")
    func cancelledRequest() async throws {
        let (logger, collector) = try await startLogger()
        defer { Task { await logger.stopLogging() } }

        let session = makeStubSession()
        let url = "https://stub.example/json?cancel=1"
        let request = session.request(url)
        request.cancel()
        _ = await request.serializingData().response

        try await Task.sleep(for: .milliseconds(300))
        #expect(collector.all.contains { $0.contains(url) } == false)
    }
}
