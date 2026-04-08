//
//  AlamofireNetworkLogger.swift
//
//  A modern, race-condition-free logger for Alamofire 5+.
//

import Alamofire
import Foundation

public enum LoggerLevel: Sendable {
    case off
    case debug  // Logs cURL, Headers, and Body (Success & Error)
    case info   // Logs Method, URL, and Status Code

    var isLoggingEnabled: Bool {
        self != .off
    }
}

// MARK: - RequestSnapshot

/// A `Sendable` value type capturing everything needed to log a completed request.
private struct RequestSnapshot: Sendable {
    let request: URLRequest
    let httpMethod: String
    let requestURL: URL
    let statusCode: Int
    let elapsedTime: Double
    let error: (any Error)?
    let responseHeaders: [String: String]?
    let data: Data?
}

public actor AlamofireNetworkLogger {

    // MARK: - Public Properties

    public static let shared = AlamofireNetworkLogger()

    public var level: LoggerLevel = .debug
    public var filterPredicate: NSPredicate?

    // MARK: - Private Properties

    private var observationTask: Task<Void, Never>?

    // MARK: - Initialization

    public init() {}

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Public Methods

    public func setLevel(_ newLevel: LoggerLevel) {
        level = newLevel
    }

    public func setFilterPredicate(_ predicate: NSPredicate?) {
        filterPredicate = predicate
    }

    public func startLogging() {
        guard observationTask == nil else { return }

        observationTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: Request.didFinishNotification) {
                guard let snap = self?.snapshot(from: notification) else { continue }
                await self?.handle(snap)
            }
        }
    }

    public func stopLogging() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Private Methods

    /// Extracts only `Sendable` value types from the notification before crossing into the actor.
    private nonisolated func snapshot(from notification: Notification) -> RequestSnapshot? {
        guard let dataRequest = notification.request as? DataRequest else { return nil }

        let finalRequest = dataRequest.task?.originalRequest ?? dataRequest.request

        guard let request = finalRequest,
              let httpMethod = request.httpMethod,
              let requestURL = request.url
        else { return nil }

        return RequestSnapshot(
            request: request,
            httpMethod: httpMethod,
            requestURL: requestURL,
            statusCode: dataRequest.response?.statusCode ?? 0,
            elapsedTime: dataRequest.metrics?.taskInterval.duration ?? 0,
            error: dataRequest.error,
            responseHeaders: dataRequest.response?.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                if let key = pair.key as? String, let value = pair.value as? String {
                    result[key] = value
                }
            },
            data: dataRequest.data
        )
    }

    private func handle(_ snap: RequestSnapshot) {
        // Apply filter if provided
        if let filter = filterPredicate, filter.evaluate(with: snap.request) {
            return
        }

        // Check if logging is enabled
        guard level.isLoggingEnabled else { return }

        logSnapshot(snap)
    }

    private func logSnapshot(_ snap: RequestSnapshot) {
        let success = (200...299).contains(snap.statusCode)
        let icon = success ? "✅" : "❌"

        logDivider()

        // 1. Log Request & cURL
        logRequestInfo(icon: icon, method: snap.httpMethod, url: snap.requestURL, request: snap.request)

        // 2. Log Response (Status & Time)
        print("\n\(icon) [RESPONSE] \(snap.statusCode) [\(String(format: "%.3fs", snap.elapsedTime))]")

        // 3. Log Error Description (if a specific network failure occurred)
        if let error = snap.error {
            print("⚠️ Error: \(error.localizedDescription)")
        }

        // 4. Log Headers & Body (even if there was an error)
        if level == .debug {
            if let headers = snap.responseHeaders {
                logHeaders(headers: headers)
            }

            if let data = snap.data, !data.isEmpty {
                print("Body:")
                prettyPrint(data)
            }
        }

        logDivider()
    }

    private func logRequestInfo(icon: String, method: String, url: URL, request: URLRequest) {
        if level == .debug {
            print("\(icon) [REQUEST] \(method) '\(url.absoluteString)'")
            print("cURL:\n\(generateCURL(from: request))")
        } else {
            print("\(icon) \(method) '\(url.absoluteString)'")
        }
    }

    private func logDivider() {
        print("---------------------")
    }

    private func logHeaders(headers: [String: String]) {
        guard !headers.isEmpty else { return }

        print("Headers: [")
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            print("  \(key): \(value)")
        }
        print("]")
    }

    private func prettyPrint(_ data: Data) {
        if let str = String(data: data, encoding: .utf8) {
            print(str)
        } else {
            print("Binary data (\(data.count) bytes)")
        }
    }

    private func generateCURL(from request: URLRequest) -> String {
        guard let url = request.url else { return "" }

        var components: [String] = ["curl -v"]

        // Add HTTP method if not GET or HEAD
        if let method = request.httpMethod, method != "GET" && method != "HEAD" {
            components.append("-X \(method)")
        }

        // Add headers
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
                components.append("-H '\(key): \(escapedValue)'")
            }
        }

        // Add body
        if let httpBody = request.httpBody, !httpBody.isEmpty {
            if let bodyString = String(data: httpBody, encoding: .utf8) {
                let escapedBody = bodyString.replacingOccurrences(of: "'", with: "'\\''")
                components.append("-d '\(escapedBody)'")
            } else {
                components.append("--data-binary <binary data \(httpBody.count) bytes>")
            }
        }

        // Add URL
        components.append("\"\(url.absoluteString)\"")

        return components.joined(separator: " ")
    }
}
