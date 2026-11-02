import XCTest
@testable import DashProtocol

final class ShareLinkTests: XCTestCase {
    private func number(_ any: Any?) -> Double { (any as! NSNumber).doubleValue }

    private func check(_ waypoint: Waypoint, _ expected: [String: Any], _ id: String) {
        if let q = expected["q"] as? String {
            XCTAssertEqual(waypoint, .query(q), id)
            return
        }
        guard case .coords(let lat, let lng, let name) = waypoint else {
            return XCTFail("\(id): expected coordinates, got \(waypoint)")
        }
        XCTAssertEqual(lat, number(expected["lat"]), accuracy: 1e-9, id)
        XCTAssertEqual(lng, number(expected["lng"]), accuracy: 1e-9, id)
        XCTAssertEqual(name, expected["name"] as? String, id)
    }

    func testEveryShareLinkVector() throws {
        for v in try Vectors.load("share-links") {
            let id = v["id"] as! String
            let text = (v["input"] as! [String: Any])["text"] as! String
            let expect = v["expect"] as! [String: Any]
            let result = ShareLinkParser.parse(text)

            switch expect["kind"] as! String {
            case "coords":
                guard case .coords(let lat, let lng, let name) = result else { XCTFail("\(id): got \(result)"); continue }
                XCTAssertEqual(lat, number(expect["lat"]), accuracy: 1e-9, id)
                XCTAssertEqual(lng, number(expect["lng"]), accuracy: 1e-9, id)
                XCTAssertEqual(name, expect["name"] as? String, id)
            case "query":
                XCTAssertEqual(result, .query(expect["q"] as! String), id)
            case "redirect":
                guard case .redirect(let url) = result else { XCTFail("\(id): got \(result)"); continue }
                XCTAssertTrue(url.hasPrefix("https://maps.app.goo.gl/AbC123"), id)
            case "directions":
                guard case .directions(let destination, let stops) = result else { XCTFail("\(id): got \(result)"); continue }
                check(destination, expect["destination"] as! [String: Any], id + " destination")
                let wantStops = expect["stops"] as! [[String: Any]]
                XCTAssertEqual(stops.count, wantStops.count, id)
                for (stop, want) in zip(stops, wantStops) { check(stop, want, id + " stop") }
            case "none":
                XCTAssertEqual(result, .none, id)
            default:
                XCTFail("\(id): unknown kind")
            }
        }
    }

    func testTrailingPunctuationIsNotPartOfTheLink() {
        XCTAssertEqual(
            ShareLinkParser.parse("Xem (https://maps.google.com/?q=10.5,106.5)."),
            .coords(lat: 10.5, lng: 106.5, name: nil))
    }

    func testEmptyAndPlainText() {
        XCTAssertEqual(ShareLinkParser.parse(""), .none)
        XCTAssertEqual(ShareLinkParser.parse("không có link nào ở đây"), .none)
    }
}
