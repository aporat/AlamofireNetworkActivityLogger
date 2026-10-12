# AlamofireNetworkActivityLogger

**AlamofireNetworkActivityLogger** is a Swift logging library for [Alamofire 5+](https://github.com/Alamofire/Alamofire) that prints each finished request as a copy-pasteable cURL command together with the response status, headers, body and timing. It is built on a Swift `actor` and observes Alamofire's `Request.didFinishNotification`, so it sees every `Session` in the process without being injected into any of them.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Faporat%2FAlamofireNetworkActivityLogger%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/aporat/AlamofireNetworkActivityLogger)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Faporat%2FAlamofireNetworkActivityLogger%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/aporat/AlamofireNetworkActivityLogger)
![GitHub Actions Workflow Status](https://github.com/aporat/AlamofireNetworkActivityLogger/actions/workflows/ci.yml/badge.svg)
[![codecov](https://codecov.io/github/aporat/AlamofireNetworkActivityLogger/graph/badge.svg?token=P0R1CXS5S5)](https://codecov.io/github/aporat/AlamofireNetworkActivityLogger)

## Features

- **Log levels**: `.debug`, `.info`, or `.off`.
- **cURL generation**: outgoing requests are formatted as valid `curl` commands, including headers added by the `Session` and any adapters. Streamed and binary bodies are described in a shell comment so the command still runs.
- **Pretty-printed JSON**: JSON response bodies are re-indented with sorted keys. Other text is printed as is; binary bodies are summarized by size.
- **Body size cap**: response bodies are truncated after 10,240 characters by default. Configurable or unlimited.
- **Header redaction**: optionally mask headers such as `Authorization` or `Set-Cookie`.
- **Request filtering**: skip requests with a `@Sendable` closure.
- **Pluggable output**: each request produces one multi-line string, delivered to `print` by default or to a sink you provide, so it can be routed into your own logging framework.
- **Covers data, upload and download requests.** Cancelled requests are skipped unless you opt in.
- **Actor-based**: all state lives in an `actor`; nothing crosses an isolation boundary that is not `Sendable`.

## Requirements

- iOS 17+ / macOS 14+ / tvOS 17+ / watchOS 10+ / visionOS 1+
- Swift 6+
- Alamofire 5.11+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/aporat/AlamofireNetworkActivityLogger.git", from: "1.0.0")
]
```

Then include `"AlamofireNetworkActivityLogger"` as a dependency in your target.

## Usage

### Start Logging

```swift
import AlamofireNetworkActivityLogger

Task {
    await AlamofireNetworkLogger.shared.startLogging()
}
```

Call this once early in your app's lifecycle, typically only in debug builds. Every Alamofire request that finishes after this point is logged, regardless of which `Session` issued it.

### Stop Logging

```swift
Task {
    await AlamofireNetworkLogger.shared.stopLogging()
}
```

### Log Level

```swift
Task {
    await AlamofireNetworkLogger.shared.setLevel(.info)
}
```

| Level    | Output                                                       |
|----------|--------------------------------------------------------------|
| `.debug` | cURL command, response headers, body, status code, timing    |
| `.info`  | HTTP method, URL, status code, timing                        |
| `.off`   | Nothing                                                      |

### Body Size

```swift
Task {
    await AlamofireNetworkLogger.shared.setMaxBodyLength(2_000)  // characters
    await AlamofireNetworkLogger.shared.setMaxBodyLength(nil)    // unlimited
}
```

### Redact Headers

Header names are matched case-insensitively and apply to both the cURL command and the response headers.

```swift
Task {
    await AlamofireNetworkLogger.shared.setRedactedHeaders(["Authorization", "Cookie", "Set-Cookie"])
}
```

### Skip Requests

```swift
Task {
    await AlamofireNetworkLogger.shared.setShouldSkip { request in
        request.url?.host == "analytics.example.com"
    }
}
```

### Cancelled Requests

Requests cancelled through Alamofire are not logged by default.

```swift
Task {
    await AlamofireNetworkLogger.shared.setLogsCancelledRequests(true)
}
```

### Route Output Elsewhere

Each finished request is delivered as a single string, so entries never interleave with each other.

```swift
Task {
    await AlamofireNetworkLogger.shared.setOutput { entry in
        myLogger.debug(entry)
    }
}
```

### Example Output

**`.debug` level:**
```
---------------------
✅ [REQUEST] POST 'https://api.example.com/users'
cURL:
curl -v -X POST -H 'Accept: application/json' -H 'Authorization: <redacted>' -H 'Content-Type: application/json' -d '{"name":"Jane"}' 'https://api.example.com/users'

✅ [RESPONSE] 201 [0.342s]
Headers: [
  Content-Type: application/json
]
Body:
{
  "id" : 1,
  "name" : "Jane"
}
---------------------
```

**`.info` level:**
```
---------------------
✅ POST 'https://api.example.com/users'

✅ [RESPONSE] 201 [0.342s]
---------------------
```

**Failed request:**
```
---------------------
❌ [REQUEST] GET 'https://api.example.com/users'
cURL:
curl -v 'https://api.example.com/users'

❌ [RESPONSE] none [0.000s]
⚠️ Error: The Internet connection appears to be offline.
---------------------
```

## Contributing

Contributions are welcome! To contribute:

1. Fork the repository.
2. Create a new branch for your feature or bug fix.
3. Commit your changes with clear, descriptive messages.
4. Push your branch and open a pull request.

Please ensure your changes include appropriate tests and follow the existing code style.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
