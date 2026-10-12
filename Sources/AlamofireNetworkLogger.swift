//
//  AlamofireNetworkLogger.swift
//
//  An actor-based request/response logger for Alamofire 5+.
//

import Alamofire
import Foundation

public enum LoggerLevel: Sendable {
    case off
    case debug  // cURL, request and response headers, body, status code, timing
    case info   // HTTP method, URL, status code, timing

    var isLoggingEnabled: Bool {
        self != .off
    }
}

public actor AlamofireNetworkLogger {

    // MARK: - Public Properties

    public static let shared = AlamofireNetworkLogger()

    /// How much detail to print for each request. Defaults to `.debug`.
    public private(set) var level: LoggerLevel = .debug

    /// Maximum number of characters of a response body to print. `nil` prints the whole body.
    /// Defaults to 10,240 characters.
    public private(set) var maxBodyLength: Int? = 10_240

    /// Header names (case-insensitive) whose values are replaced with `<redacted>` in both the
    /// cURL command and the response headers. Empty by default.
    public private(set) var redactedHeaders: Set<String> = []

    /// Whether requests that were explicitly cancelled are logged. Defaults to `false`.
    public private(set) var logsCancelledRequests = false

    // MARK: - Private Properties

    private var shouldSkip: (@Sendable (URLRequest) -> Bool)?
    private var output: @Sendable (String) -> Void = { print($0) }
    private var observationTask: Task<Void, Never>?

    // MARK: - Initialization

    public init() {}

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Configuration

    public func setLevel(_ newLevel: LoggerLevel) {
        level = newLevel
    }

    public func setMaxBodyLength(_ length: Int?) {
        maxBodyLength = length
    }

    public func setRedactedHeaders(_ names: Set<String>) {
        redactedHeaders = names
    }

    public func setLogsCancelledRequests(_ enabled: Bool) {
        logsCancelledRequests = enabled
    }

    /// Requests for which `predicate` returns `true` are not logged.
    public func setShouldSkip(_ predicate: (@Sendable (URLRequest) -> Bool)?) {
        shouldSkip = predicate
    }

    /// Where each rendered log entry is sent. Defaults to `print`. Each request produces exactly
    /// one call with the complete, multi-line entry.
    public func setOutput(_ sink: @escaping @Sendable (String) -> Void) {
        output = sink
    }

    // MARK: - Start / Stop

    public func startLogging() {
        guard observationTask == nil else { return }

        observationTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: Request.didFinishNotification) {
                guard let request = notification.request,
                      let snapshot = RequestSnapshot(request: request)
                else { continue }
                await self?.handle(snapshot)
            }
        }
    }

    public func stopLogging() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Internal

    func handle(_ snapshot: RequestSnapshot) {
        guard level.isLoggingEnabled else { return }
        if snapshot.isCancelled, !logsCancelledRequests { return }
        if let shouldSkip, shouldSkip(snapshot.request) { return }

        output(LogFormatter.render(
            snapshot,
            level: level,
            maxBodyLength: maxBodyLength,
            redactedHeaders: redactedHeaders
        ))
    }
}

// MARK: - RequestSnapshot

/// Everything needed to render one finished request, captured as `Sendable` values before
/// crossing into the actor.
struct RequestSnapshot: Sendable {
    enum Kind: Sendable {
        case data
        case download
        case other
    }

    let kind: Kind
    let request: URLRequest
    let httpMethod: String
    let requestURL: URL
    let statusCode: Int?
    let elapsedTime: Double
    let error: (any Error)?
    let isCancelled: Bool
    let responseHeaders: [String: String]
    let data: Data?
    let downloadedFileURL: URL?

    var hasResponse: Bool { statusCode != nil }

    var isSuccess: Bool {
        guard error == nil, let statusCode else { return false }
        return (200...299).contains(statusCode)
    }

    var contentType: String? {
        responseHeaders.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
    }

    init(
        kind: Kind,
        request: URLRequest,
        httpMethod: String,
        requestURL: URL,
        statusCode: Int?,
        elapsedTime: Double,
        error: (any Error)?,
        isCancelled: Bool,
        responseHeaders: [String: String],
        data: Data?,
        downloadedFileURL: URL?
    ) {
        self.kind = kind
        self.request = request
        self.httpMethod = httpMethod
        self.requestURL = requestURL
        self.statusCode = statusCode
        self.elapsedTime = elapsedTime
        self.error = error
        self.isCancelled = isCancelled
        self.responseHeaders = responseHeaders
        self.data = data
        self.downloadedFileURL = downloadedFileURL
    }

    init?(request: Request) {
        // `task.originalRequest` includes headers added by the session and adapters;
        // `request.request` is the fallback when no task was ever created.
        guard let urlRequest = request.task?.originalRequest ?? request.request,
              let httpMethod = urlRequest.httpMethod,
              let requestURL = urlRequest.url
        else { return nil }

        let kind: Kind
        var data: Data?
        var downloadedFileURL: URL?

        switch request {
        case let dataRequest as DataRequest:
            kind = .data
            data = dataRequest.data
        case let downloadRequest as DownloadRequest:
            kind = .download
            downloadedFileURL = downloadRequest.fileURL
        default:
            kind = .other
        }

        let headers = (request.response?.allHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String else { return }
            result[key] = pair.value as? String ?? String(describing: pair.value)
        }

        self.init(
            kind: kind,
            request: urlRequest,
            httpMethod: httpMethod,
            requestURL: requestURL,
            statusCode: request.response?.statusCode,
            elapsedTime: request.metrics?.taskInterval.duration ?? 0,
            error: request.error,
            isCancelled: request.error?.isExplicitlyCancelledError ?? false,
            responseHeaders: headers,
            data: data,
            downloadedFileURL: downloadedFileURL
        )
    }
}

// MARK: - LogFormatter

enum LogFormatter {

    static let divider = "---------------------"
    static let redactedPlaceholder = "<redacted>"

    static func render(
        _ snapshot: RequestSnapshot,
        level: LoggerLevel,
        maxBodyLength: Int?,
        redactedHeaders: Set<String>
    ) -> String {
        let icon = snapshot.isSuccess ? "✅" : "❌"
        var lines: [String] = [divider]

        // Request
        if level == .debug {
            lines.append("\(icon) [REQUEST] \(snapshot.httpMethod) '\(snapshot.requestURL.absoluteString)'")
            lines.append("cURL:")
            lines.append(cURLCommand(for: snapshot.request, redactedHeaders: redactedHeaders))
        } else {
            lines.append("\(icon) \(snapshot.httpMethod) '\(snapshot.requestURL.absoluteString)'")
        }

        // Response status and timing
        let status = snapshot.statusCode.map(String.init) ?? "none"
        lines.append("")
        lines.append("\(icon) [RESPONSE] \(status) [\(String(format: "%.3fs", snapshot.elapsedTime))]")

        if let error = snapshot.error {
            lines.append("⚠️ Error: \(error.localizedDescription)")
        }

        // Headers and body
        if level == .debug {
            if !snapshot.responseHeaders.isEmpty {
                lines.append("Headers: [")
                for (key, value) in snapshot.responseHeaders.sorted(by: { $0.key < $1.key }) {
                    let shown = isRedacted(key, in: redactedHeaders) ? redactedPlaceholder : value
                    lines.append("  \(key): \(shown)")
                }
                lines.append("]")
            }

            switch snapshot.kind {
            case .data:
                if let data = snapshot.data, !data.isEmpty {
                    lines.append("Body:")
                    lines.append(renderBody(data, contentType: snapshot.contentType, maxBodyLength: maxBodyLength))
                }
            case .download:
                if let fileURL = snapshot.downloadedFileURL {
                    lines.append("Downloaded to: \(fileURL.path)")
                }
            case .other:
                break
            }
        }

        lines.append(divider)
        return lines.joined(separator: "\n")
    }

    static func renderBody(_ data: Data, contentType: String?, maxBodyLength: Int?) -> String {
        let text: String

        if isJSON(contentType), let pretty = prettyPrintedJSON(data) {
            text = pretty
        } else if contentType == nil || isTextual(contentType),
                  let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            return "Binary data (\(data.count) bytes)"
        }

        guard let maxBodyLength, text.count > maxBodyLength else { return text }
        let omitted = text.count - maxBodyLength
        return String(text.prefix(maxBodyLength)) + "\n… [truncated \(omitted) characters]"
    }

    /// Builds a copy-pasteable `curl` command. Bodies that cannot be reproduced (streamed or
    /// binary) are described in a trailing shell comment so the command stays valid.
    static func cURLCommand(for request: URLRequest, redactedHeaders: Set<String>) -> String {
        guard let url = request.url else { return "" }

        var components = ["curl -v"]
        var notes: [String] = []

        if let method = request.httpMethod, method != "GET", method != "HEAD" {
            components.append("-X \(method)")
        }

        for (key, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            let shown = isRedacted(key, in: redactedHeaders) ? redactedPlaceholder : value
            components.append("-H \(shellQuoted("\(key): \(shown)"))")
        }

        if let body = request.httpBody, !body.isEmpty {
            if let string = String(data: body, encoding: .utf8) {
                components.append("-d \(shellQuoted(string))")
            } else {
                notes.append("# request body omitted: binary data (\(body.count) bytes)")
            }
        } else if request.httpBodyStream != nil {
            notes.append("# request body omitted: streamed body (e.g. multipart upload)")
        }

        components.append(shellQuoted(url.absoluteString))

        return ([components.joined(separator: " ")] + notes).joined(separator: "\n")
    }

    // MARK: Helpers

    static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isRedacted(_ header: String, in redactedHeaders: Set<String>) -> Bool {
        redactedHeaders.contains { $0.caseInsensitiveCompare(header) == .orderedSame }
    }

    static func isJSON(_ contentType: String?) -> Bool {
        contentType?.lowercased().contains("json") ?? false
    }

    static func isTextual(_ contentType: String?) -> Bool {
        guard let type = contentType?.lowercased() else { return false }
        return ["text/", "json", "xml", "javascript", "x-www-form-urlencoded"].contains { type.contains($0) }
    }

    static func prettyPrintedJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
              )
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}
