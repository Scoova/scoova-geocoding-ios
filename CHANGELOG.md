# Changelog

All notable changes to `ScoovaGeocoding` (Swift) are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-05-25

### Added
- Initial release of `ScoovaGeocoding` Swift package — extracted from the
  unified `ScoovaSDK` `places` namespace and rebuilt as a focused
  geocoding-only library.
- `ScoovaGeocodingClient` actor with `search`, `autocomplete`, `reverse`,
  `place`, `searchStructured`, and `batch` (up to 100 mixed forward /
  reverse queries per request).
- Built-in locale (`?locale=` + `Accept-Language`) and API-key
  (`X-API-Key`) handling. API key falls back to `SCOOVA_API_KEY` env var
  then to the public `demo` key.
- `GeocodingTransport` protocol so tests can stub `URLSession` without
  spinning up a server. `URLSessionTransport` is the default.
- Platform support: iOS 15+, macOS 12+, tvOS 15+, watchOS 8+.

### Notes
- Numbered `1.1.0` to match the rest of the geocoding product family
  (web / Android / RN). There is no `1.0.0` Swift tag.
