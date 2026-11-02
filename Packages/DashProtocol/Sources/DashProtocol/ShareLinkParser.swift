import Foundation

/// A stop on a route: exact coordinates (with the place name if the link had one), or a text to search.
public enum Waypoint: Equatable {
    case coords(lat: Double, lng: Double, name: String?)
    case query(String)
}

public enum ShareLinkResult: Equatable {
    /// A place with coordinates.
    case coords(lat: Double, lng: Double, name: String?)
    /// A text to search (MapKit local search, Photon, Nominatim...). Let the rider confirm the top result.
    case query(String)
    /// A Google Maps directions link: the destination and the stops between origin and destination.
    case directions(destination: Waypoint, stops: [Waypoint])
    /// A short link (maps.app.goo.gl): request it WITHOUT following redirects, read the Location header,
    /// and parse that URL with this parser again (up to about 5 hops).
    case redirect(String)
    /// Not a maps link, or coordinates out of range. Say so; do not guess.
    case none
}

/// Turns the text a share sheet hands the app (Google Maps, Apple Maps) into a destination.
/// Pure and offline; the redirect hop is done by the caller. Rules: docs/how-it-works/routing-options.md.
/// Google changes link shapes without notice, so this is fragile: test with links from your own phone.
public enum ShareLinkParser {

    public static func parse(_ text: String) -> ShareLinkResult {
        guard let url = firstURL(in: text) else { return .none }
        let parts = split(url)
        let host = parts.host.lowercased()

        if host == "maps.app.goo.gl" || (host == "goo.gl" && parts.path.hasPrefix("/maps")) {
            return .redirect(url)
        }
        guard isMapsLink(host: host, path: parts.path) else { return .none }

        let components = parts.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let params = queryParams(parts.query)

        // 1. Directions: /maps/dir/<origin>/<stop>.../<destination>/@view/data=...
        if let dirIndex = components.firstIndex(of: "dir") {
            let segments = components[(dirIndex + 1)...].prefix { !$0.hasPrefix("@") && !$0.hasPrefix("data=") }
            if !segments.isEmpty {
                let data = components.first { $0.hasPrefix("data=") } ?? ""
                return directions(segments: Array(segments), data: data)
            }
        }

        // 2. Place link: the place itself is !3d<lat>!4d<lng> in the data part, NOT the @ viewport.
        var placeName: String?
        if let placeIndex = components.firstIndex(of: "place"), placeIndex + 1 < components.count,
           !components[placeIndex + 1].hasPrefix("@") {
            placeName = decode(components[placeIndex + 1])
        }
        if let c = captures(#"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#, in: url),
           let lat = Double(c[0]), let lng = Double(c[1]) {
            return inRange(lat, lng) ? .coords(lat: lat, lng: lng, name: placeName) : .none
        }

        // 3. Query parameters with coordinates: ?q= ?ll= ?query= ?destination= ?daddr=
        for key in ["ll", "q", "query", "destination", "daddr"] {
            guard let value = params[key] else { continue }
            switch parseCoords(value) {
            case .valid(let lat, let lng):
                var name: String?
                if key == "ll", let q = params["q"], !q.isEmpty, case .notCoords = parseCoords(q) { name = q }
                return .coords(lat: lat, lng: lng, name: name)
            case .invalid:
                return .none
            case .notCoords:
                continue
            }
        }

        // 4. A place name with no coordinates: search it (beats a viewport, which can be far from the place).
        if let name = placeName, !name.isEmpty { return .query(name) }

        // 5. Text in the query parameters: search it.
        for key in ["q", "query", "destination", "daddr"] {
            if let value = params[key], !value.isEmpty { return .query(value) }
        }

        // 6. Only a map view: @<lat>,<lng>,<zoom>z
        for component in components {
            if let c = captures(#"^@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)"#, in: component),
               let lat = Double(c[0]), let lng = Double(c[1]) {
                return inRange(lat, lng) ? .coords(lat: lat, lng: lng, name: nil) : .none
            }
        }
        return .none
    }

    // MARK: Directions

    private static func directions(segments: [String], data: String) -> ShareLinkResult {
        let dataCoords = waypointCoords(in: data)   // one entry per waypoint, in order; nil = no coordinates
        var waypoints: [Waypoint] = []
        for (index, segment) in segments.enumerated() {
            let text = decode(segment)
            switch parseCoords(text) {
            case .valid(let lat, let lng):
                waypoints.append(.coords(lat: lat, lng: lng, name: nil))
            case .invalid:
                return .none
            case .notCoords:
                // Pair by position. A waypoint without coordinates is searched by its text:
                // never reuse another waypoint's coordinates (the origin's, for example).
                if index < dataCoords.count, let c = dataCoords[index], inRange(c.lat, c.lng) {
                    waypoints.append(.coords(lat: c.lat, lng: c.lng, name: text))
                } else {
                    waypoints.append(.query(text))
                }
            }
        }
        if waypoints.count == 1 { return .directions(destination: waypoints[0], stops: []) }
        let stops = Array(waypoints[1..<(waypoints.count - 1)])
        return .directions(destination: waypoints[waypoints.count - 1], stops: stops)
    }

    /// Reads `!1m5!1m1!1s<id>!2m2!1d<lng>!2d<lat>` (a waypoint with coordinates) and `!1m0` (one without).
    private static func waypointCoords(in data: String) -> [(lat: Double, lng: Double)?] {
        let pattern = #"!1m0|!1m5!1m1!1s[^!]+!2m2!1d(-?\d+(?:\.\d+)?)!2d(-?\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = data as NSString
        var result: [(lat: Double, lng: Double)?] = []
        for match in regex.matches(in: data, range: NSRange(location: 0, length: ns.length)) {
            if match.range(at: 1).location != NSNotFound,
               let lng = Double(ns.substring(with: match.range(at: 1))),
               let lat = Double(ns.substring(with: match.range(at: 2))) {
                result.append((lat: lat, lng: lng))
            } else {
                result.append(nil)
            }
        }
        return result
    }

    // MARK: Helpers

    private enum Coord { case valid(Double, Double), invalid, notCoords }

    private static func parseCoords(_ text: String) -> Coord {
        guard let c = captures(#"^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$"#, in: text),
              let lat = Double(c[0]), let lng = Double(c[1]) else { return .notCoords }
        return inRange(lat, lng) ? .valid(lat, lng) : .invalid
    }

    private static func inRange(_ lat: Double, _ lng: Double) -> Bool {
        lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
    }

    private static func isMapsLink(host: String, path: String) -> Bool {
        if host.hasPrefix("maps.google.") || host.hasPrefix("maps.apple.") { return true }
        if host.contains("google.") && (path == "/maps" || path.hasPrefix("/maps/")) { return true }
        return false
    }

    /// The first http(s) URL in the shared text (Google Maps shares a name, address lines, then a link).
    private static func firstURL(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var url = ns.substring(with: match.range)
        while let last = url.last, ".,;:)]".contains(last) { url.removeLast() }
        return url
    }

    private static func split(_ url: String) -> (host: String, path: String, query: String) {
        guard let schemeEnd = url.range(of: "://") else { return ("", "", "") }
        var rest = String(url[schemeEnd.upperBound...])
        if let hash = rest.firstIndex(of: "#") { rest = String(rest[..<hash]) }
        var query = ""
        if let q = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: q)...])
            rest = String(rest[..<q])
        }
        if let slash = rest.firstIndex(of: "/") {
            return (String(rest[..<slash]), String(rest[slash...]), query)
        }
        return (rest, "", query)
    }

    private static func queryParams(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = kv.first else { continue }
            let value = kv.count > 1 ? decode(String(kv[1])) : ""
            if result[String(key)] == nil { result[String(key)] = value }
        }
        return result
    }

    /// Google writes spaces as "+" and the rest percent-encoded.
    private static func decode(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
    }
}
