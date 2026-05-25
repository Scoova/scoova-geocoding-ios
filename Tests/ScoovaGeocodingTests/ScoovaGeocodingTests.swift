import XCTest
@testable import ScoovaGeocoding

/// In-memory transport stub. Records the most recent request and replies
/// with a canned `(status, body)` pair.
final class StubTransport: GeocodingTransport, @unchecked Sendable {
    var lastURL: URL?
    var lastMethod: String = ""
    var lastHeaders: [String: String] = [:]
    var lastBody: Data?
    var status: Int = 200
    var body: Data

    init(status: Int = 200, body: String = #"{"type":"FeatureCollection","features":[]}"#) {
        self.status = status
        self.body = Data(body.utf8)
    }

    func send(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) async throws -> (Int, Data) {
        self.lastURL = url
        self.lastMethod = method
        self.lastHeaders = headers
        self.lastBody = body
        return (status, self.body)
    }
}

final class ScoovaGeocodingTests: XCTestCase {
    func test_search_hitsV1Search() async throws {
        let t = StubTransport()
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "k",
            transport: t
        )
        _ = try await c.search("Cairo")
        XCTAssertEqual(t.lastMethod, "GET")
        XCTAssertEqual(t.lastURL?.path, "/v1/search")
        let qi = URLComponents(url: t.lastURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(qi.contains(where: { $0.name == "text" && $0.value == "Cairo" }))
    }

    func test_search_forwardsFocusBoundarySizeLang() async throws {
        let t = StubTransport()
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "k",
            transport: t
        )
        _ = try await c.search(
            "coffee",
            focusPoint: FocusPoint(lat: 30.04, lon: 31.24),
            boundaryCountry: ["EG", "AE"],
            layers: ["venue", "address"],
            size: 5,
            lang: "ar-EG"
        )
        let qi = URLComponents(url: t.lastURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(qi.first { $0.name == "focus.point.lat" }?.value, "30.04")
        XCTAssertEqual(qi.first { $0.name == "boundary.country" }?.value, "EG,AE")
        XCTAssertEqual(qi.first { $0.name == "layers" }?.value, "venue,address")
        XCTAssertEqual(qi.first { $0.name == "size" }?.value, "5")
        XCTAssertEqual(qi.first { $0.name == "lang" }?.value, "ar-EG")
    }

    func test_reverse_usesPointParams() async throws {
        let t = StubTransport()
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "k",
            transport: t
        )
        _ = try await c.reverse(lat: 30.04, lon: 31.24, size: 1)
        XCTAssertEqual(t.lastURL?.path, "/v1/reverse")
        let qi = URLComponents(url: t.lastURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(qi.first { $0.name == "point.lat" }?.value, "30.04")
        XCTAssertEqual(qi.first { $0.name == "point.lon" }?.value, "31.24")
    }

    func test_place_joinsIds() async throws {
        let t = StubTransport()
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "k",
            transport: t
        )
        _ = try await c.place(["place data:locality:101751119", "place data:country:85632343"])
        let qi = URLComponents(url: t.lastURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(
            qi.first { $0.name == "ids" }?.value,
            "place data:locality:101751119,place data:country:85632343"
        )
    }

    func test_structured_flattensFields() async throws {
        let t = StubTransport()
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "k",
            transport: t
        )
        _ = try await c.searchStructured(["locality": "Cairo", "country": "EG"], size: 3)
        XCTAssertEqual(t.lastURL?.path, "/v1/search/structured")
        let qi = URLComponents(url: t.lastURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(qi.first { $0.name == "locality" }?.value, "Cairo")
        XCTAssertEqual(qi.first { $0.name == "country" }?.value, "EG")
    }

    func test_parsesFeatures() async throws {
        let body = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","geometry":{"type":"Point","coordinates":[31.24,30.04]},
           "properties":{"name":"Cairo","label":"Cairo, Egypt"}}
        ]}
        """
        let t = StubTransport(body: body)
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "k",
            transport: t
        )
        let res = try await c.search("Cairo")
        XCTAssertEqual(res.features.count, 1)
        XCTAssertEqual(res.features[0].lon, 31.24, accuracy: 0.0001)
        XCTAssertEqual(res.features[0].lat, 30.04, accuracy: 0.0001)
        XCTAssertEqual(res.features[0].label, "Cairo, Egypt")
    }

    func test_throwsOnNon2xx() async {
        let t = StubTransport(status: 502, body: "boom")
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "k",
            transport: t
        )
        do {
            _ = try await c.search("Cairo")
            XCTFail("expected throw")
        } catch let GeocodingError.http(status, _) {
            XCTAssertEqual(status, 502)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func test_sendsAuthAndLocaleHeaders() async throws {
        let t = StubTransport()
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "sk_live",
            locale: "fr",
            transport: t
        )
        _ = try await c.search("Paris")
        XCTAssertEqual(t.lastHeaders["X-API-Key"], "sk_live")
        XCTAssertEqual(t.lastHeaders["Accept-Language"], "fr")
        let qi = URLComponents(url: t.lastURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(qi.first { $0.name == "locale" }?.value, "fr")
    }

    func test_batch_postsToBatchEndpoint() async throws {
        let body = """
        {"success":true,"data":{"count":2,"results":[
          {"id":"a","top":{"type":"Feature","geometry":{"type":"Point","coordinates":[31.24,30.04]},
                           "properties":{"label":"Cairo"}}},
          {"id":"b","error":"no result"}
        ]}}
        """
        let t = StubTransport(body: body)
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "k",
            transport: t
        )
        let res = try await c.batch([
            BatchItem(id: "a", text: "Cairo"),
            BatchItem(id: "b", lat: 1, lon: 2),
        ])
        XCTAssertEqual(t.lastMethod, "POST")
        XCTAssertEqual(t.lastURL?.path, "/v1/batch")
        XCTAssertNotNil(t.lastBody)
        let sentJson = try JSONSerialization.jsonObject(with: t.lastBody!) as? [String: Any]
        let items = sentJson?["items"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 2)
        XCTAssertEqual(items?[0]["id"] as? String, "a")
        XCTAssertEqual(items?[0]["text"] as? String, "Cairo")
        XCTAssertEqual(res.count, 2)
        XCTAssertEqual(res.results[0].top?.label, "Cairo")
        XCTAssertEqual(res.results[1].error, "no result")
    }

    func test_batch_rejectsEmptyAndOversize() async {
        let c = ScoovaGeocodingClient(
            baseURL: URL(string: "https://example.test")!,
            apiKey: "k",
            transport: StubTransport()
        )
        do { _ = try await c.batch([]); XCTFail() }
        catch GeocodingError.invalidInput { /* ok */ }
        catch { XCTFail("wrong error: \(error)") }

        let many = (0..<101).map { BatchItem(id: String($0), text: "x") }
        do { _ = try await c.batch(many); XCTFail() }
        catch GeocodingError.invalidInput { /* ok */ }
        catch { XCTFail("wrong error: \(error)") }
    }
}
