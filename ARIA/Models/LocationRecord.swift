import Foundation

/// A location update record to sync to the ARIA server.
struct LocationRecord: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: String
    let placeName: String?
    let locality: String?
    let administrativeArea: String?
    let country: String?
    let speed: Double?
    let course: Double?

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case accuracy
        case timestamp
        case placeName = "place_name"
        case locality
        case administrativeArea = "administrative_area"
        case country
        case speed
        case course
    }
}

/// Wrapper for the location sync request body.
struct LocationSyncRequest: Codable, Sendable {
    let location: LocationRecord
}

/// Response from POST /api/device-location.
struct LocationSyncResponse: Codable, Sendable {
    let saved: Bool
}

/// A CLVisit record to sync to the ARIA server.
struct VisitRecord: Codable, Sendable {
    let arrivalDate: String
    let departureDate: String?
    let latitude: Double
    let longitude: Double
    let accuracy: Double?

    enum CodingKeys: String, CodingKey {
        case arrivalDate = "arrival_date"
        case departureDate = "departure_date"
        case latitude
        case longitude
        case accuracy
    }
}

/// Wrapper for a single visit sync request body.
struct VisitSyncRequest: Codable, Sendable {
    let visit: VisitRecord
}

/// Response from POST /api/device-visits.
struct VisitSyncResponse: Codable, Sendable {
    let saved: Int
}
