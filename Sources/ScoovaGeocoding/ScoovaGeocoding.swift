import Foundation

// ─── Option / result types ─────────────────────────────────────────────

public struct FocusPoint: Sendable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

public struct BoundaryCircle: Sendable {
    public let lat: Double
    public let lon: Double
    public let radiusKm: Double
    public init(lat: Double, lon: Double, radiusKm: Double) {
        self.lat = lat; self.lon = lon; self.radiusKm = radiusKm
    }
}

public struct BoundaryRect: Sendable {
    public let minLon: Double
    public let minLat: Double
    public let maxLon: Double
    public let maxLat: Double
    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon; self.minLat = minLat
        self.maxLon = maxLon; self.maxLat = maxLat
    }
}

/// One Pelias feature. `properties` is the full GeoJSON properties bag
/// kept as a raw JSON map so callers can read anything Pelias returns
/// (gid, layer, source, accuracy, addendum, …) without the SDK needing
/// to track every field. `@unchecked Sendable` because `[String: Any]`
/// can't be statically proven sendable, but the bag is decoded once
/// from JSON and never mutated.
public struct GeoFeature: @unchecked Sendable {
    public let lon: Double
    public let lat: Double
    public let properties: [String: Any]
    /// Best-effort human label — falls back to `name` if `label` is absent.
    public var label: String {
        (properties["label"] as? String) ?? (properties["name"] as? String) ?? ""
    }

    public init(lon: Double, lat: Double, properties: [String: Any]) {
        self.lon = lon
        self.lat = lat
        self.properties = properties
    }
}

public struct GeoResponse: @unchecked Sendable {
    public let features: [GeoFeature]
    public let raw: [String: Any]

    static func parse(_ data: Data) -> GeoResponse {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return GeoResponse(features: [], raw: [:])
        }
        let features = ((json["features"] as? [[String: Any]]) ?? []).map(featureFromJSON)
        return GeoResponse(features: features, raw: json)
    }

    private init(features: [GeoFeature], raw: [String: Any]) {
        self.features = features
        self.raw = raw
    }
}

private func featureFromJSON(_ f: [String: Any]) -> GeoFeature {
    let geom = f["geometry"] as? [String: Any]
    let coords = (geom?["coordinates"] as? [Any]) ?? []
    let lon = (coords.first as? Double) ?? ((coords.first as? Int).map(Double.init) ?? 0)
    let lat = (coords.dropFirst().first as? Double) ?? ((coords.dropFirst().first as? Int).map(Double.init) ?? 0)
    let props = (f["properties"] as? [String: Any]) ?? [:]
    return GeoFeature(lon: lon, lat: lat, properties: props)
}

/// One item in a `batch` request. Provide `text` for a forward query,
/// `lat` + `lon` for a reverse query. `id` is echoed back on the matching
/// result row so you can join to your own records.
public struct BatchItem: Sendable {
    public let id: String?
    public let text: String?
    public let lat: Double?
    public let lon: Double?
    public init(id: String? = nil, text: String? = nil, lat: Double? = nil, lon: Double? = nil) {
        self.id = id; self.text = text; self.lat = lat; self.lon = lon
    }
    func toJSON() -> [String: Any] {
        var d: [String: Any] = [:]
        if let id { d["id"] = id }
        if let text { d["text"] = text }
        if let lat { d["lat"] = lat }
        if let lon { d["lon"] = lon }
        return d
    }
}

public struct BatchResultRow: @unchecked Sendable {
    public let id: String?
    public let top: GeoFeature?
    public let error: String?
}

public struct BatchResponse: @unchecked Sendable {
    public let count: Int
    public let results: [BatchResultRow]

    static func parse(_ data: Data) -> BatchResponse {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return BatchResponse(count: 0, results: [])
        }
        // Server may wrap `{ success, data: { count, results } }` — unwrap.
        let body = (root["data"] as? [String: Any]) ?? root
        let rows = ((body["results"] as? [[String: Any]]) ?? []).map { r -> BatchResultRow in
            let id = r["id"] as? String
            let top: GeoFeature? = (r["top"] as? [String: Any]).map(featureFromJSON)
            let err = r["error"] as? String
            return BatchResultRow(id: id, top: top, error: err)
        }
        return BatchResponse(count: (body["count"] as? Int) ?? rows.count, results: rows)
    }

    private init(count: Int, results: [BatchResultRow]) {
        self.count = count
        self.results = results
    }
}

// ─── Errors ───────────────────────────────────────────────────────────

public enum GeocodingError: Error, Sendable, CustomStringConvertible {
    case http(statusCode: Int, body: String)
    case decode(String)
    case transport(Error)
    case invalidInput(String)

    public var description: String {
        switch self {
        case .http(let code, let body): return "GeocodingError.http(\(code), \(body.prefix(120)))"
        case .decode(let m):            return "GeocodingError.decode(\(m))"
        case .transport(let e):         return "GeocodingError.transport(\(e))"
        case .invalidInput(let m):      return "GeocodingError.invalidInput(\(m))"
        }
    }
}

// ─── Transport ────────────────────────────────────────────────────────

/// Pluggable HTTP transport. Default implementation uses `URLSession`.
/// Tests can swap this for an in-memory stub.
public protocol GeocodingTransport: Sendable {
    func send(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) async throws -> (Int, Data)
}

public struct URLSessionTransport: GeocodingTransport {
    public let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) async throws -> (Int, Data) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.httpBody = body
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        req.timeoutInterval = 30
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            return (0, data)
        }
        return (http.statusCode, data)
    }
}

// ─── Client ───────────────────────────────────────────────────────────

/// Pelias-compatible geocoding client for `api.scoo-va.info/api/v1/geocoding`.
///
///     let client = ScoovaGeocodingClient(
///         apiKey: ProcessInfo.processInfo.environment["SCOOVA_API_KEY"],
///         locale: "fr"
///     )
///
///     let hit = try await client.search("Tour Eiffel")
///     let rev = try await client.reverse(lat: 48.8584, lon: 2.2945)
///     let bat = try await client.batch([
///         BatchItem(id: "a", text: "Times Square"),
///         BatchItem(id: "b", lat: 40.7484, lon: -73.9857),
///     ])
///
/// Every method is `async` and throws ``GeocodingError`` on non-2xx
/// responses or transport failures.
public actor ScoovaGeocodingClient {
    private let baseURL: URL
    private let apiKey: String
    private let locale: String
    private let androidPackage: String?
    private let iosBundleId: String?
    private let transport: GeocodingTransport

    /// - parameters:
    ///   - baseURL: gateway base. Defaults to `https://api.scoo-va.info/api/v1/geocoding`.
    ///   - apiKey: Scoova API key. Sent as `X-API-Key`. If nil, the client
    ///     reads the `SCOOVA_API_KEY` environment variable, then falls
    ///     back to the public `demo` key (rate-limited).
    ///   - locale: default locale (e.g. `"en"`, `"fr"`, `"ar-EG"`). Sent
    ///     on every request as both `?locale=` and `Accept-Language`. A
    ///     per-call `lang` argument still overrides.
    ///   - androidPackage / iosBundleId: identity headers for the
    ///     gateway's key-restriction enforcement.
    ///   - transport: pluggable HTTP layer for tests.
    public init(
        baseURL: URL = URL(string: "https://api.scoo-va.info/api/v1/geocoding")!,
        apiKey: String? = nil,
        locale: String = "en",
        androidPackage: String? = nil,
        iosBundleId: String? = Bundle.main.bundleIdentifier,
        transport: GeocodingTransport = URLSessionTransport()
    ) {
        // Trim any trailing slash so `path + "/v1/..."` is always exactly one slash.
        let s = baseURL.absoluteString
        let trimmed = s.hasSuffix("/") ? String(s.dropLast()) : s
        self.baseURL = URL(string: trimmed) ?? baseURL
        self.apiKey = apiKey
            ?? ProcessInfo.processInfo.environment["SCOOVA_API_KEY"]
            ?? "demo"
        self.locale = locale
        self.androidPackage = androidPackage
        self.iosBundleId = iosBundleId
        self.transport = transport
    }

    // ─── Public surface ───────────────────────────────────────────────

    /// Forward search — "Burj Khalifa" → list of features.
    public func search(
        _ text: String,
        focusPoint: FocusPoint? = nil,
        boundaryCircle: BoundaryCircle? = nil,
        boundaryRect: BoundaryRect? = nil,
        boundaryCountry: [String]? = nil,
        layers: [String]? = nil,
        sources: [String]? = nil,
        size: Int? = nil,
        lang: String? = nil
    ) async throws -> GeoResponse {
        var items: [URLQueryItem] = [URLQueryItem(name: "text", value: text)]
        applySearchParams(
            &items,
            focusPoint: focusPoint, boundaryCircle: boundaryCircle, boundaryRect: boundaryRect,
            boundaryCountry: boundaryCountry, layers: layers, sources: sources,
            size: size, lang: lang
        )
        return try await getGeo("/v1/search", items: items)
    }

    /// Type-ahead autocomplete — partial text → suggestions.
    public func autocomplete(
        _ text: String,
        focusPoint: FocusPoint? = nil,
        boundaryCountry: [String]? = nil,
        layers: [String]? = nil,
        sources: [String]? = nil,
        size: Int? = nil,
        lang: String? = nil
    ) async throws -> GeoResponse {
        var items: [URLQueryItem] = [URLQueryItem(name: "text", value: text)]
        if let f = focusPoint {
            items.append(URLQueryItem(name: "focus.point.lat", value: String(f.lat)))
            items.append(URLQueryItem(name: "focus.point.lon", value: String(f.lon)))
        }
        if let c = boundaryCountry, !c.isEmpty {
            items.append(URLQueryItem(name: "boundary.country", value: c.joined(separator: ",")))
        }
        if let l = layers, !l.isEmpty {
            items.append(URLQueryItem(name: "layers", value: l.joined(separator: ",")))
        }
        if let s = sources, !s.isEmpty {
            items.append(URLQueryItem(name: "sources", value: s.joined(separator: ",")))
        }
        if let n = size {
            items.append(URLQueryItem(name: "size", value: String(n)))
        }
        items.append(URLQueryItem(name: "lang", value: lang ?? locale))
        return try await getGeo("/v1/autocomplete", items: items)
    }

    /// Reverse geocode — coordinates → nearest features.
    public func reverse(
        lat: Double, lon: Double,
        size: Int? = nil,
        layers: [String]? = nil,
        sources: [String]? = nil,
        boundaryCircleRadiusKm: Double? = nil,
        boundaryCountry: [String]? = nil,
        lang: String? = nil
    ) async throws -> GeoResponse {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "point.lat", value: String(lat)),
            URLQueryItem(name: "point.lon", value: String(lon)),
        ]
        if let n = size {
            items.append(URLQueryItem(name: "size", value: String(n)))
        }
        if let l = layers, !l.isEmpty {
            items.append(URLQueryItem(name: "layers", value: l.joined(separator: ",")))
        }
        if let s = sources, !s.isEmpty {
            items.append(URLQueryItem(name: "sources", value: s.joined(separator: ",")))
        }
        if let r = boundaryCircleRadiusKm {
            items.append(URLQueryItem(name: "boundary.circle.radius", value: String(r)))
        }
        if let c = boundaryCountry, !c.isEmpty {
            items.append(URLQueryItem(name: "boundary.country", value: c.joined(separator: ",")))
        }
        items.append(URLQueryItem(name: "lang", value: lang ?? locale))
        return try await getGeo("/v1/reverse", items: items)
    }

    /// Lookup one or more Pelias gids (e.g. `whosonfirst:locality:101751119`).
    public func place(_ ids: [String]) async throws -> GeoResponse {
        try await getGeo("/v1/place", items: [
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "lang", value: locale),
        ])
    }

    /// Structured search — address, locality, country broken into fields.
    public func searchStructured(
        _ query: [String: String],
        focusPoint: FocusPoint? = nil,
        boundaryCircle: BoundaryCircle? = nil,
        boundaryRect: BoundaryRect? = nil,
        boundaryCountry: [String]? = nil,
        layers: [String]? = nil,
        sources: [String]? = nil,
        size: Int? = nil,
        lang: String? = nil
    ) async throws -> GeoResponse {
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        applySearchParams(
            &items,
            focusPoint: focusPoint, boundaryCircle: boundaryCircle, boundaryRect: boundaryRect,
            boundaryCountry: boundaryCountry, layers: layers, sources: sources,
            size: size, lang: lang
        )
        return try await getGeo("/v1/search/structured", items: items)
    }

    /// Batch geocode — up to 100 mixed forward (`text`) or reverse
    /// (`lat`+`lon`) queries in a single round-trip. Each result is
    /// returned in input order with the supplied `id` echoed back.
    public func batch(_ items: [BatchItem]) async throws -> BatchResponse {
        if items.isEmpty {
            throw GeocodingError.invalidInput("batch: items cannot be empty")
        }
        if items.count > 100 {
            throw GeocodingError.invalidInput("batch: max 100 items per request")
        }
        let body = try JSONSerialization.data(
            withJSONObject: ["items": items.map { $0.toJSON() }],
            options: []
        )
        let url = try buildURL(path: "/v1/batch", items: [])
        let (status, data) = try await send(
            url: url, method: "POST",
            headers: authHeaders(extra: ["Content-Type": "application/json"]),
            body: body
        )
        if !(200..<300).contains(status) {
            throw GeocodingError.http(statusCode: status, body: previewString(data))
        }
        return BatchResponse.parse(data)
    }

    // ─── internals ────────────────────────────────────────────────────

    private nonisolated func applySearchParams(
        _ items: inout [URLQueryItem],
        focusPoint: FocusPoint?,
        boundaryCircle: BoundaryCircle?,
        boundaryRect: BoundaryRect?,
        boundaryCountry: [String]?,
        layers: [String]?,
        sources: [String]?,
        size: Int?,
        lang: String?
    ) {
        if let f = focusPoint {
            items.append(URLQueryItem(name: "focus.point.lat", value: String(f.lat)))
            items.append(URLQueryItem(name: "focus.point.lon", value: String(f.lon)))
        }
        if let bc = boundaryCircle {
            items.append(URLQueryItem(name: "boundary.circle.lat", value: String(bc.lat)))
            items.append(URLQueryItem(name: "boundary.circle.lon", value: String(bc.lon)))
            items.append(URLQueryItem(name: "boundary.circle.radius", value: String(bc.radiusKm)))
        }
        if let br = boundaryRect {
            items.append(URLQueryItem(name: "boundary.rect.min_lon", value: String(br.minLon)))
            items.append(URLQueryItem(name: "boundary.rect.min_lat", value: String(br.minLat)))
            items.append(URLQueryItem(name: "boundary.rect.max_lon", value: String(br.maxLon)))
            items.append(URLQueryItem(name: "boundary.rect.max_lat", value: String(br.maxLat)))
        }
        if let c = boundaryCountry, !c.isEmpty {
            items.append(URLQueryItem(name: "boundary.country", value: c.joined(separator: ",")))
        }
        if let l = layers, !l.isEmpty {
            items.append(URLQueryItem(name: "layers", value: l.joined(separator: ",")))
        }
        if let s = sources, !s.isEmpty {
            items.append(URLQueryItem(name: "sources", value: s.joined(separator: ",")))
        }
        if let n = size {
            items.append(URLQueryItem(name: "size", value: String(n)))
        }
        items.append(URLQueryItem(name: "lang", value: lang ?? locale))
    }

    private func buildURL(path: String, items: [URLQueryItem]) throws -> URL {
        let cleaned = path.hasPrefix("/") ? path : "/" + path
        var comps = URLComponents(url: baseURL.appendingPathComponent(cleaned),
                                  resolvingAgainstBaseURL: false)
        if comps == nil {
            comps = URLComponents(string: baseURL.absoluteString + cleaned)
        }
        var all: [URLQueryItem] = [URLQueryItem(name: "locale", value: locale)]
        all.append(contentsOf: items)
        comps?.queryItems = all
        guard let url = comps?.url else {
            throw GeocodingError.invalidInput("could not build URL for \(path)")
        }
        return url
    }

    private func authHeaders(extra: [String: String] = [:]) -> [String: String] {
        var h: [String: String] = [
            "X-API-Key": apiKey,
            "Accept": "application/json",
            "Accept-Language": locale,
        ]
        if let p = androidPackage { h["X-Android-Package"] = p }
        if let b = iosBundleId   { h["X-Ios-Bundle-Identifier"] = b }
        for (k, v) in extra { h[k] = v }
        return h
    }

    private func send(
        url: URL, method: String,
        headers: [String: String], body: Data?
    ) async throws -> (Int, Data) {
        do {
            return try await transport.send(url: url, method: method, headers: headers, body: body)
        } catch {
            throw GeocodingError.transport(error)
        }
    }

    private func getGeo(_ path: String, items: [URLQueryItem]) async throws -> GeoResponse {
        let url = try buildURL(path: path, items: items)
        let (status, data) = try await send(
            url: url, method: "GET",
            headers: authHeaders(), body: nil
        )
        if !(200..<300).contains(status) {
            throw GeocodingError.http(statusCode: status, body: previewString(data))
        }
        return GeoResponse.parse(data)
    }
}

private func previewString(_ data: Data) -> String {
    String(data: data, encoding: .utf8)?.prefix(200).description ?? ""
}
