# AlamofireNetworkActivityLogger

**AlamofireNetworkActivityLogger** is a Swift logging library for [Alamofire 5+](https://github.com/Alamofire/Alamofire) that captures and prints detailed network activity — including cURL commands, headers, response bodies, and timing — using a modern, race-condition-free `actor`-based design backed by Swift Concurrency.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Faporat%2FAlamofireNetworkActivityLogger%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/aporat/AlamofireNetworkActivityLogger)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Faporat%2FAlamofireNetworkActivityLogger%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/aporat/AlamofireNetworkActivityLogger)
![GitHub Actions Workflow Status](https://github.com/aporat/AlamofireNetworkActivityLogger/actions/workflows/ci.yml/badge.svg)
[![codecov](https://codecov.io/github/aporat/AlamofireNetworkActivityLogger/graph/badge.svg?token=OHF9AE0KMC)](https://codecov.io/github/aporat/AlamofireNetworkActivityLogger)

## Features

- **Structured log levels**: Choose between `.debug`, `.info`, and `.off` to control verbosity.
- **cURL generation**: Automatically formats outgoing requests as copy-pasteable `curl` commands.
- **Pretty-printed JSON**: Response bodies are formatted for readability when possible.
- **Request filtering**: Optionally supply an `NSPredicate` to suppress specific requests from logs.
- **Actor-based concurrency**: Built with Swift's `actor` model — no locks, no races.
- **Async notification observation**: Uses `AsyncStream` over `NotificationCenter` for safe, structured observation.

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

Call this once early in your app's lifecycle (e.g. in `AppDelegate` or your app's `init`). All Alamofire requests will be logged automatically after this point.

### Stop Logging

```swift
Task {
    await AlamofireNetworkLogger.shared.stopLogging()
}
```

### Set the Log Level

```swift
Task {
    await AlamofireNetworkLogger.shared.setLevel(.info)
}
```

| Level    | Output                                              |
|----------|-----------------------------------------------------|
| `.debug` | cURL command, headers, status code, body, timing    |
| `.info`  | HTTP method, URL, status code, timing               |
| `.off`   | Nothing (logging disabled)                          |

### Filter Requests

Use an `NSPredicate` to suppress specific requests from appearing in the logs:

```swift
Task {
    await AlamofireNetworkLogger.shared.setFilterPredicate(NSPredicate { request, _ in
        guard let url = (request as? URLRequest)?.url else { return false }
        return url.absoluteString.contains("analytics")
    })
}
```

Any request where the predicate evaluates to `true` will be silently skipped.

### Example Output

**`.debug` level:**
```
---------------------
✅ [REQUEST] GET 'https://api.example.com/users'
cURL:
curl -v -H 'Accept: application/json' -H 'Authorization: Bearer abc123' "https://api.example.com/users"

✅ [RESPONSE] 200 [0.342s]
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
✅ GET 'https://api.example.com/users'

✅ [RESPONSE] 200 [0.342s]
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
