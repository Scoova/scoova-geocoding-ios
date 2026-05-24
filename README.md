# ScoovaGeocoding (Swift)

Pelias-compatible geocoding client for `geocoding.scoo-va.info` — forward
search, autocomplete, reverse, place lookup, structured search, and a
synchronous batch endpoint (up to 100 mixed forward/reverse queries per
request).

Pure Swift Package, async/await, zero third-party dependencies.

## Install (Swift Package Manager)

Xcode → **File ▸ Add Package Dependencies…** and paste:

```
https://github.com/Scoova/scoova-geocoding-ios
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/Scoova/scoova-geocoding-ios", from: "1.1.0"),
```

```swift
.target(name: "MyApp", dependencies: [
    .product(name: "ScoovaGeocoding", package: "scoova-geocoding-ios"),
]),
```

## Platforms

| platform  | min |
| --------- | --- |
| iOS       | 15  |
| macOS     | 12  |
| tvOS      | 15  |
| watchOS   | 8   |

## Usage

```swift
import ScoovaGeocoding

let client = ScoovaGeocodingClient(
    apiKey: ProcessInfo.processInfo.environment["SCOOVA_API_KEY"], // → "demo" if nil
    locale: "fr"  // default Accept-Language + ?locale=
)

let hit = try await client.search(
    "Tour Eiffel",
    focusPoint: FocusPoint(lat: 48.85, lon: 2.29),
    size: 5
)

let rev = try await client.reverse(lat: 48.8584, lon: 2.2945, size: 1)

let suggestions = try await client.autocomplete("Tour Eif")

let pl = try await client.place(["whosonfirst:locality:101751119"])

let structured = try await client.searchStructured([
    "locality": "Cairo", "country": "EG",
])

let batch = try await client.batch([
    BatchItem(id: "a", text: "Times Square"),
    BatchItem(id: "b", lat: 40.7484, lon: -73.9857),
])
for row in batch.results {
    print("\(row.id ?? "—") -> \(row.top?.label ?? row.error ?? "no result")")
}
```

## Initializer parameters

| arg              | type                  | default                              |
| ---------------- | --------------------- | ------------------------------------ |
| `baseURL`        | `URL`                 | `https://geocoding.scoo-va.info`     |
| `apiKey`         | `String?`             | `SCOOVA_API_KEY` env, then `demo`    |
| `locale`         | `String`              | `"en"`                               |
| `androidPackage` | `String?`             | nil                                  |
| `iosBundleId`    | `String?`             | `Bundle.main.bundleIdentifier`       |
| `transport`      | `GeocodingTransport`  | `URLSessionTransport()`              |

## Tests

```
swift test
```

## License

Apache-2.0 — see [LICENSE](./LICENSE).
