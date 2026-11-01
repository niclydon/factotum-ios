import Foundation

/// `GET /api/mobile/estate` — aggregate-only estate snapshot over the
/// factotum_* tables (OB-66209): the Macs' Factotum registries (apps,
/// packages, services, actions per host) plus the factotum_devices rows.
/// Counts, ages, and states only; no private content.
struct MobileEstate: Codable, Sendable, Equatable {
    let contractVersion: String
    let generatedAt: String
    let hosts: [Host]
    let devices: [Device]
    let summary: Summary

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case generatedAt = "generated_at"
        case hosts, devices, summary
    }

    struct Host: Codable, Sendable, Equatable, Identifiable {
        var id: String { host }
        let host: String
        let registryGeneratedAt: String?
        let registrySyncedAt: String?
        let registryAgeS: Int?
        let registryStale: Bool
        let apps: Apps
        let packages: Packages
        let services: Services
        let actions: Actions

        enum CodingKeys: String, CodingKey {
            case host
            case registryGeneratedAt = "registry_generated_at"
            case registrySyncedAt = "registry_synced_at"
            case registryAgeS = "registry_age_s"
            case registryStale = "registry_stale"
            case apps, packages, services, actions
        }

        struct Apps: Codable, Sendable, Equatable {
            let installed: Int
            let running: Int
        }

        struct Packages: Codable, Sendable, Equatable {
            let total: Int
            let outdated: Int
        }

        struct Services: Codable, Sendable, Equatable {
            let total: Int
            let byDesiredState: [String: Int]

            enum CodingKeys: String, CodingKey {
                case total
                case byDesiredState = "by_desired_state"
            }

            var running: Int { byDesiredState["running"] ?? 0 }
        }

        struct Actions: Codable, Sendable, Equatable {
            let total: Int
        }

        /// Host keys are machine names ("laptop", "server"); render
        /// them the way the owner refers to the machines.
        var displayName: String {
            switch host {
            case "laptop": return "Laptop"
            case "build-mac": return "Build Mac"
            case "server": return "Server"
            case "gpu-node": return "GPU Node"
            default: return host.capitalized
            }
        }
    }

    struct Device: Codable, Sendable, Equatable, Identifiable {
        var id: String { deviceId }
        let deviceId: String
        let deviceName: String?
        let model: String?
        let osVersion: String?
        let appVersion: String?
        let appBuild: String?
        let bundleId: String?
        let distribution: String?
        let profileExpiresAt: String?
        let pushTokenPresent: Bool
        let buildFirstSeenAt: String?
        let firstRegisteredAt: String?
        let lastSeenAt: String?

        enum CodingKeys: String, CodingKey {
            case deviceId = "device_id"
            case deviceName = "device_name"
            case model
            case osVersion = "os_version"
            case appVersion = "app_version"
            case appBuild = "app_build"
            case bundleId = "bundle_id"
            case distribution
            case profileExpiresAt = "profile_expires_at"
            case pushTokenPresent = "push_token_present"
            case buildFirstSeenAt = "build_first_seen_at"
            case firstRegisteredAt = "first_registered_at"
            case lastSeenAt = "last_seen_at"
        }
    }

    struct Summary: Codable, Sendable, Equatable {
        let hostsReporting: Int
        let hostsStale: Int
        let totalOutdatedPackages: Int

        enum CodingKeys: String, CodingKey {
            case hostsReporting = "hosts_reporting"
            case hostsStale = "hosts_stale"
            case totalOutdatedPackages = "total_outdated_packages"
        }
    }

    static let empty = MobileEstate(
        contractVersion: "",
        generatedAt: "",
        hosts: [],
        devices: [],
        summary: Summary(hostsReporting: 0, hostsStale: 0, totalOutdatedPackages: 0)
    )
}

/// `GET /api/mobile/estate/hosts/:hostId` — per-host detail behind the
/// aggregates (upgrades-scan item 4, 3.4.0): the actual app, package,
/// service, and action rows from one host's Factotum registry, so the
/// phone can answer "which packages are outdated on the build Mac" instead of
/// only showing a count. Packages arrive outdated-first from the server.
struct MobileEstateHostDetail: Codable, Sendable, Equatable {
    let host: String
    let generatedAt: String
    let apps: [App]
    let packages: [Package]
    let services: [Service]
    let actions: [Action]

    enum CodingKeys: String, CodingKey {
        case host
        case generatedAt = "generated_at"
        case apps, packages, services, actions
    }

    struct App: Codable, Sendable, Equatable, Identifiable {
        var id: String { bundleId }
        let bundleId: String
        let name: String?
        let version: String?
        let installed: Bool
        let running: Bool

        enum CodingKeys: String, CodingKey {
            case bundleId = "bundle_id"
            case name, version, installed, running
        }

        var displayName: String { name ?? bundleId }
    }

    struct Package: Codable, Sendable, Equatable, Identifiable {
        var id: String { name }
        let name: String
        let installedVersion: String?
        let latestVersion: String?
        let outdated: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case installedVersion = "installed_version"
            case latestVersion = "latest_version"
            case outdated
        }
    }

    struct Service: Codable, Sendable, Equatable, Identifiable {
        var id: String { serviceId }
        let serviceId: String
        let launchdLabel: String?
        let kind: String?
        let desiredState: String?

        enum CodingKeys: String, CodingKey {
            case serviceId = "service_id"
            case launchdLabel = "launchd_label"
            case kind
            case desiredState = "desired_state"
        }

        var displayName: String { launchdLabel ?? serviceId }
    }

    struct Action: Codable, Sendable, Equatable, Identifiable {
        var id: String { actionId }
        let actionId: String
        let name: String?
        let op: String?
        let status: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case actionId = "action_id"
            case name, op, status
            case updatedAt = "updated_at"
        }
    }
}

/// DEBUG contract checks for the estate DTOs (upgrades-scan item 9):
/// decode fixture JSON shaped exactly like the server responses and trap
/// on drift, so a server-side field rename fails the self-check gate
/// instead of surfacing as a blank Estate tab on the phone.
enum MobileEstateContract {
    #if DEBUG
    static func runSelfCheck() {
        let decoder = JSONDecoder()
        let estateJSON = """
        {"contract_version":"1.3.0","generated_at":"2026-10-18T17:00:00Z",
         "hosts":[{"host":"server","registry_generated_at":null,"registry_synced_at":"2026-10-18 16:59:00+00",
           "registry_age_s":60,"registry_stale":false,
           "apps":{"installed":93,"running":41},"packages":{"total":98,"outdated":5},
           "services":{"total":28,"by_desired_state":{"running":25,"stopped":3}},"actions":{"total":44}}],
         "devices":[],"summary":{"hosts_reporting":2,"hosts_stale":0,"total_outdated_packages":12}}
        """
        let detailJSON = """
        {"host":"server","generated_at":"2026-10-18T17:00:00Z",
         "apps":[{"bundle_id":"io.example.backend","name":"Example Backend","version":"1.0.0","installed":true,"running":true},
                 {"bundle_id":"io.example.unknown","name":null,"version":null,"installed":true,"running":false}],
         "packages":[{"name":"typescript","installed_version":"5.4.0","latest_version":"5.6.0","outdated":true},
                     {"name":"tsx","installed_version":"4.0.0","latest_version":"4.0.0","outdated":false}],
         "services":[{"service_id":"example-api","launchd_label":"io.example.example-api","kind":"service","desired_state":"running"}],
         "actions":[{"action_id":"a1","name":"deploy","op":"restart","status":"done","updated_at":"2026-10-18 15:00:00+00"}]}
        """
        do {
            let estate = try decoder.decode(MobileEstate.self, from: Data(estateJSON.utf8))
            assert(estate.hosts.first?.packages.outdated == 5, "estate aggregate decode drifted")
            assert(estate.hosts.first?.services.running == 25, "estate services decode drifted")
            let detail = try decoder.decode(MobileEstateHostDetail.self, from: Data(detailJSON.utf8))
            assert(detail.packages.first?.outdated == true, "host detail package decode drifted")
            assert(detail.packages.last?.installedVersion == "4.0.0", "host detail version keys drifted")
            assert(detail.actions.first?.updatedAt != nil, "host detail action timestamp key drifted")
            assert(detail.apps.last?.displayName == "io.example.unknown", "host detail app null-name fallback drifted")
            assert(detail.services.first?.displayName == "io.example.example-api", "host detail service label drifted")
        } catch {
            assertionFailure("MobileEstateContract decode failed: \(error)")
        }
    }
    #endif
}

/// Server timestamps arrive as Postgres `::text` ("2026-10-18 14:44:11.497+00")
/// or ISO 8601 depending on the column; accept both, plus plain ISO without
/// fractional seconds. Returns nil when neither parses — callers then show
/// the raw string rather than nothing.
func parseServerDate(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: raw) { return d }
    iso.formatOptions = [.withInternetDateTime]
    if let d = iso.date(from: raw) { return d }
    let pg = DateFormatter()
    pg.locale = Locale(identifier: "en_US_POSIX")
    for format in ["yyyy-MM-dd HH:mm:ss.SSSSSSx", "yyyy-MM-dd HH:mm:ssx", "yyyy-MM-dd HH:mm:ss.SSSSSSZ", "yyyy-MM-dd HH:mm:ssZ"] {
        pg.dateFormat = format
        if let d = pg.date(from: raw) { return d }
    }
    return nil
}
