import Foundation

/// Canonical app-facing contract fixtures — synthetic JSON
/// for the backend-owned response shapes the ARIA iOS app decodes, plus a decode
/// self-check that proves every fixture decodes through its real Codable model.
///
/// Why here (not an XCTest): this repo has no XCTest target (see
/// docs/aria-ios-nexus-release-verification.md §4). This is a dedicated,
/// reviewable fixtures module — NOT hidden inside a one-off test — and
/// `runSelfCheck()` (wired in `AppDelegate`, `#if DEBUG`) decodes each fixture at
/// launch so a missing optional field, a changed key, or a proxy error body
/// breaks the debug build instead of making the shipped app look empty/broken.
///
/// Documented CLI verification (the build Mac / macOS):
///   `bash scripts/verify-contract-fixtures.sh`
/// That script re-decodes the same JSON catalog (JSON files under
/// `fixtures/mobile-api.v1/`) through Codable DTOs and fails non-zero on
/// contract breakage. Keep this enum, the JSON files, and the script in lockstep.
///
/// Fixture ↔ surface mapping: `docs/contract-fixtures.md`.
/// Nexus mirror: `packages/api/src/routes/__tests__/aria-ios-contract-fixtures.test.ts`.
/// All content is SYNTHETIC — no private card/message bodies, real person names,
/// raw transcripts, or secrets.
/// Chat SSE shapes are pinned separately by `ChatEventContract` (OB-52236).
enum ContractFixtures {

    /// Contract version these fixtures pin (matches nexus `mobile-api` v1).
    static let contractVersion = "1.3.0"

    // MARK: - Review cards (GET /api/mobile/review-cards; POST /:id/decide) — contract 1.1.0

    /// Two open Life-domain cards: an identity card with a reply-capture action (note required)
    /// and a knowledge-graph card with a select. Mirrors fixtures/mobile-api.v1/review-cards-open.json.
    static let reviewCardsOpen = """
    {
      "contract_version": "1.3.0",
      "generated_at": "2026-09-06T12:00:00.000Z",
      "cards": [
    {
      "id": "11111111-1111-4111-8111-111111111111",
      "kind": "unlinked_identifier_review",
      "domain": "identity",
      "title": "Unlinked identifier: +1 555 0100",
      "body": "Seen in 3 synthetic messages. Suggested match: **Sample Person**.",
      "posted_at": "2026-09-06T10:00:00.000Z",
      "expires_at": "2026-09-13T10:00:00.000Z",
      "status": "posted",
      "selected_decision": null,
      "decided_at": null,
      "decided_by": null,
      "actions": [
        {
          "label": "Link suggested person",
          "style": "success",
          "decision": "link_existing"
        },
        {
          "label": "Link to a person…",
          "style": "secondary",
          "decision": "link_person"
        },
        {
          "label": "Dismiss (spam/not real)",
          "style": "danger",
          "decision": "dismissed"
        }
      ],
      "selects": [],
      "reply_capture_actions": {
        "link_person": "To link this identifier to a person, reply with the person's name or id."
      }
    },
    {
      "id": "22222222-2222-4222-8222-222222222222",
      "kind": "knowledge_fact_candidate_review",
      "domain": "knowledge_graph",
      "title": "3 fact candidates from a synthetic note",
      "body": "- Sample Person works at Example Co\\n- Sample Person lives in Springfield",
      "posted_at": "2026-09-06T11:00:00.000Z",
      "expires_at": null,
      "status": "posted",
      "selected_decision": null,
      "decided_at": null,
      "decided_by": null,
      "actions": [
        {
          "label": "✅ Accept these",
          "style": "success",
          "decision": "accept"
        },
        {
          "label": "❌ Reject these",
          "style": "danger",
          "decision": "reject"
        },
        {
          "label": "🔍 Investigate",
          "style": "primary",
          "decision": "investigate"
        }
      ],
      "selects": [
        {
          "action": "pick_target",
          "placeholder": "Pick a person",
          "min_values": 1,
          "max_values": 1,
          "options": [
            {
              "label": "Sample Person",
              "value": "p-1",
              "description": "contact"
            }
          ]
        }
      ],
      "reply_capture_actions": {}
    }
      ]
    }
    """

    /// One decided card (from this phone) — the Recent list / receipt shape.
    static let reviewCardsRecent = """
    {
      "contract_version": "1.3.0",
      "generated_at": "2026-09-06T12:00:00.000Z",
      "cards": [
    {
      "id": "33333333-3333-4333-8333-333333333333",
      "kind": "term_resolution_confirm",
      "domain": "memoir",
      "title": "Term: 'the cabin' → Sample Lake House",
      "body": "Synthetic memoir term resolution.",
      "posted_at": "2026-09-05T09:00:00.000Z",
      "expires_at": null,
      "status": "decided",
      "selected_decision": "dismissed",
      "decided_at": "2026-09-06T12:30:00.000Z",
      "decided_by": "ios:synthetic@example.com",
      "actions": [],
      "selects": [],
      "reply_capture_actions": {}
    }
      ]
    }
    """

    static let reviewCardDecideOk = """
    {
      "card": {
    "id": "33333333-3333-4333-8333-333333333333",
    "kind": "term_resolution_confirm",
    "domain": "memoir",
    "title": "Term: 'the cabin' → Sample Lake House",
    "body": "Synthetic memoir term resolution.",
    "posted_at": "2026-09-05T09:00:00.000Z",
    "expires_at": null,
    "status": "decided",
    "selected_decision": "dismissed",
    "decided_at": "2026-09-06T12:30:00.000Z",
    "decided_by": "ios:synthetic@example.com",
    "actions": [],
    "selects": [],
    "reply_capture_actions": {}
      }
    }
    """

    /// 409 body: the card was decided on another surface first.
    static let reviewCardDecideConflict = """
    {
      "error": "already_decided",
      "card": {
    "id": "33333333-3333-4333-8333-333333333333",
    "kind": "term_resolution_confirm",
    "domain": "memoir",
    "title": "Term: 'the cabin' → Sample Lake House",
    "body": "Synthetic memoir term resolution.",
    "posted_at": "2026-09-05T09:00:00.000Z",
    "expires_at": null,
    "status": "decided",
    "selected_decision": "dismissed",
    "decided_at": "2026-09-06T12:30:00.000Z",
    "decided_by": "discord:synthetic",
    "actions": [],
    "selects": [],
    "reply_capture_actions": {}
      }
    }
    """

    /// 400 body: a reply-capture action was sent without a note.
    static let reviewCardDecideNoteRequired = """
    {
      "error": "note_required",
      "prompt": "To link this identifier to a person, reply with the person's name or id."
    }
    """

    // MARK: - Model picker (GET /v1/forge/models)

    /// Mix of pickable-local, pickable-cloud, deprecated (hidden), retired (hidden),
    /// and a non-text embedding model (hidden). `isPickable` must keep exactly the
    /// first two (Desk parity — see docs/chat-model-contract.md).
    static let forgeModels = """
    {"data":[
      {"id":"example-local","type":"text","provider":null,"status":"available","pickable":true},
      {"id":"example-cloud","type":"text","provider":"anthropic","status":"available","pickable":true},
      {"id":"example-permissive","type":"text","provider":null,"status":"available","pickable":true,"deprecated_until":"2026-08-01"},
      {"id":"example-retired","type":"text","provider":null,"status":"available","pickable":true,"retired_on":"2026-06-01"},
      {"id":"example-embed","type":"embedding","provider":null,"status":"available","pickable":true}
    ]}
    """

    // MARK: - History (GET /v1/channels/aria-direct/history)

    static let channelHistory = """
    {"messages":[
      {"id":1,"channel_id":"aria-direct","sender_id":"user","message_type":"text","content":"synthetic user turn","created_at":"2026-07-12T00:00:00.000Z"},
      {"id":2,"channel_id":"aria-direct","sender_id":"assistant","content":"synthetic assistant turn","created_at":"2026-07-12T00:00:01.000Z"}
    ],"has_more":false}
    """
    static let channelHistoryEmpty = #"{"messages":[]}"#

    // MARK: - Device sync responses (POST /api/health-data, /api/device-*)

    /// HealthKit batch ack. Extra server fields stay optional on the DTO so additive
    /// server keys never break the app.
    static let healthSync = #"{"synced":3,"inserted":3,"conflicted":0,"errored":0,"total":3}"#
    static let locationSync = #"{"saved":true}"#
    static let visitSync = #"{"saved":2}"#
    static let activitySync = #"{"saved":true}"#
    static let activityBulkSync = #"{"saved":4,"total":4,"valid":4}"#
    static let musicSync = #"{"synced":5,"playlists_synced":1}"#
    static let deviceEventsAck = #"{"accepted":["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"],"duplicate":["bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"],"rejected":[{"id":null,"error":"id must be a UUID"}]}"#
    static let healthFilesAck = #"{"accepted":["hk:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"],"duplicate":[],"rejected":[]}"#

    // MARK: - Push registration (POST/DELETE /api/notifications/device-token)

    /// Registration/unregistration ack. App decodes as EmptyResponse (extra keys ignored).
    static let deviceTokenOk = #"{"ok":true}"#

    // MARK: - Command ask (POST /api/command/ask)

    /// Matches worker `CommandAskResult` camelCase shape (see packages/worker command-ask.ts).
    static let commandAsk = """
    {"answer":"Synthetic grounded answer with no private content.",
     "toolCalls":[{"tool":"example_unified_view","ok":true,"result":"synthetic hit count: 2"}],
     "readToolCount":1,"steps":2,"truncated":false}
    """

    // MARK: - Inbox (GET /api/inbox) — app DTO shape; route may be dark/backend-missing

    /// List response. Item fields use snake_case CodingKeys; list totals are camelCase
    /// (matches `InboxListResponse` property names with default Codable).
    static let inboxList = """
    {"items":[
      {"id":"inbox-synthetic-1","title":"Synthetic insight","body":"Synthetic body with no private content.",
       "category":"proactive_insight","urgency":"standard","source":"pie",
       "source_id":"src-synthetic","insight_id":"insight-synthetic-1","conversation_id":null,
       "is_read":false,"read_at":null,"feedback_rating":null,"feedback_comment":null,
       "created_at":"2026-07-12T00:00:00.000Z"}
    ],"total":1,"unreadCount":1}
    """
    static let inboxListEmpty = #"{"items":[],"total":0,"unreadCount":0}"#

    // MARK: - Notification settings (device preferences / methods)

    static let notificationMethods = """
    {"methods":[
      {"id":"method-synthetic-1","channel":"push","label":"iPhone-synthetic",
       "config":{"device_token":"synthetic-token-not-real","is_sandbox":true},
       "is_enabled":true,
       "push_preferences":{"notifications":true,"reports":false,"urgency_filter":"all"},
       "created_at":"2026-07-12T00:00:00.000Z","updated_at":"2026-07-12T00:00:00.000Z"}
    ]}
    """

    static let devicePreferences = """
    {"devices":[
      {"id":"method-synthetic-1","label":"iPhone-synthetic","is_enabled":true,
       "push_preferences":{"notifications":true,"reports":false,"urgency_filter":"all"}}
    ]}
    """

    // MARK: - Proactive settings / insights (app DTO shape; route may be dark)

    static let proactiveSettings = """
    {"settings":{
      "risk_level":"balanced",
      "urgent_delivery_methods":["push"],
      "standard_delivery_methods":["push","digest"],
      "digest_schedule":{"morning":"08:00","evening":"20:00"},
      "confidence_threshold":0.7,
      "gmail_check_interval_seconds":900,
      "fast_track_patterns":{
        "auto_adapt_enabled":true,
        "universal_patterns":["\\\\b911\\\\b"],
        "adaptive_patterns":[{"pattern":"\\\\bsynthetic\\\\b","reason":"fixture only"}],
        "context_summary":"synthetic",
        "last_regenerated_at":"2026-07-12T00:00:00.000Z"
      }
    }}
    """

    static let proactiveInsights = """
    {"insights":[
      {"id":"insight-synthetic-1","title":"Synthetic insight","body":"Synthetic insight body.",
       "reasoning":"fixture reasoning","category":"routine","urgency":"standard",
       "confidence":0.82,"status":"delivered","feedback_rating":null,"feedback_comment":null,
       "created_at":"2026-07-12T00:00:00.000Z","delivered_at":"2026-07-12T00:05:00.000Z",
       "expires_at":null,
       "evidence":{"snapshots":[{"source":"calendar","summary":"synthetic meeting block"}],
                   "triggered_at":"2026-07-12T00:00:00.000Z"}}
    ]}
    """
    static let proactiveInsightsEmpty = #"{"insights":[]}"#

    // MARK: - Mobile bootstrap (GET /api/mobile/bootstrap, OB-52301)

    /// Config-only success payload (contract 1.1.0; review cards live). No private content.
    static let mobileBootstrapReady = """
    {
      "contract_version": "1.3.0",
      "server_time": "2026-07-20T12:00:00.000Z",
      "supported_features": {
    "chat": true,
    "command_ask": true,
    "health_sync": true,
    "location_sync": true,
    "activity_sync": true,
    "music_sync": true,
    "push": true,
    "inbox": false,
    "proactive": false,
    "notifications_settings": false,
    "review_cards": true,
    "device_events": true,
    "health_files": true
      },
      "push": {
    "device_token_registration": true
      },
      "data_source_freshness_thresholds": {
    "health_hours": 36,
    "location_hours": 12,
    "activity_hours": 24,
    "music_hours": 48
      },
      "app_version": {
    "minimum": null,
    "recommended": null
      },
      "route_flags": {
    "GET /api/mobile/bootstrap": "live",
    "GET /api/inbox": "backend-missing",
    "GET /api/mobile/review-cards": "live",
    "POST /api/mobile/review-cards/:id/decide": "live",
    "POST /api/device-events": "live",
    "POST /api/health-files": "live"
      }
    }
    """

    /// Minimal: review cards not advertised (older server) — Review tab shows unavailable.
    static let mobileBootstrapMinimal = """
    {
      "contract_version": "1.3.0",
      "server_time": "2026-07-20T12:00:00.000Z",
      "supported_features": {
    "chat": true,
    "command_ask": true,
    "health_sync": true,
    "location_sync": true,
    "activity_sync": true,
    "music_sync": true,
    "push": true,
    "inbox": false,
    "proactive": false,
    "notifications_settings": false,
    "review_cards": false
      },
      "push": {
    "device_token_registration": true
      },
      "data_source_freshness_thresholds": {
    "health_hours": 36,
    "location_hours": 12,
    "activity_hours": 24,
    "music_hours": 48
      },
      "app_version": {
    "minimum": null,
    "recommended": null
      },
      "route_flags": {
    "GET /api/mobile/bootstrap": "live",
    "GET /api/inbox": "backend-missing",
    "GET /api/mobile/review-cards": "backend-missing",
    "POST /api/mobile/review-cards/:id/decide": "backend-missing"
      }
    }
    """

    // MARK: - Mobile freshness (GET /api/mobile/freshness, OB-52302)

    /// Aggregate-only freshness with mixed status classes (synthetic).
    static let mobileFreshnessMixed = """
    {"contract_version":"1.0.0","server_time":"2026-07-20T12:00:00.000Z",
     "sources":[
       {"source_key":"healthkit","app_key":"health","display_label":"Health","kind":"device_sync",
        "status":"fresh","last_seen_at":"2026-07-20T10:00:00.000Z","age_bucket":"lt_6h",
        "expected_cadence_hours":36,"failure_class":null,"user_facing_state":"ok"},
       {"source_key":"device_location","app_key":"location","display_label":"Location","kind":"device_sync",
        "status":"stale","last_seen_at":"2026-07-19T12:00:00.000Z","age_bucket":"1d_3d",
        "expected_cadence_hours":12,"failure_class":"past_expected_cadence","user_facing_state":"stale"},
       {"source_key":"device_motion_activity","app_key":"motion","display_label":"Motion & Activity","kind":"device_sync",
        "status":"error","last_seen_at":"2026-07-20T08:00:00.000Z","age_bucket":"lt_6h",
        "expected_cadence_hours":24,"failure_class":"registry_error","user_facing_state":"error"},
       {"source_key":"device_music","app_key":"music","display_label":"Music","kind":"device_sync",
        "status":"empty","last_seen_at":null,"age_bucket":"never",
        "expected_cadence_hours":48,"failure_class":null,"user_facing_state":"empty"},
       {"source_key":"cards","app_key":"cards","display_label":"Cards / Console","kind":"surface",
        "status":"fresh","last_seen_at":null,"age_bucket":"lt_6h",
        "expected_cadence_hours":null,"failure_class":null,"user_facing_state":"ok"},
       {"source_key":"chat","app_key":"chat","display_label":"Chat / History","kind":"surface",
        "status":"fresh","last_seen_at":"2026-07-20T11:30:00.000Z","age_bucket":"lt_6h",
        "expected_cadence_hours":168,"failure_class":null,"user_facing_state":"ok"},
       {"source_key":"push","app_key":"push","display_label":"Push notifications","kind":"push",
        "status":"fresh","last_seen_at":null,"age_bucket":"lt_6h",
        "expected_cadence_hours":null,"failure_class":null,"user_facing_state":"ok"}
     ],
     "summary":{"fresh":4,"stale":1,"error":1,"empty":1,"unknown":0,"disabled":0,"overall":"error"},
     "platform":{"bridge_health":"ok","worker_queue":{"pending":12,"status":"ok"}}}
    """

    /// One Big Thing composites (Factotum 4.0 W3, OB-66557). Mirrors
    /// fixtures/mobile-api.v1/mobile-one-big-thing.json.
    /// Ack for POST /api/mobile/photo-intelligence (Factotum 4.0 W9 Lens,
    /// OB-66559). Mirrors fixtures/mobile-api.v1/mobile-photo-intelligence.json.
    static let mobilePhotoIntelligence = """
    {
      "received": 2,
      "inserted": 2,
      "duplicates": 0
    }
    """

    /// Ack for POST /api/mobile/photo-terms (photo text index
    /// prototype, OB-66960). Mirrors
    /// fixtures/mobile-api.v1/mobile-photo-terms.json.
    static let mobilePhotoTerms = """
    {
      "received_terms": 10,
      "inserted": 9,
      "duplicates": 1
    }
    """

    /// Ack for POST /api/mobile/photo-intelligence/enrich
    /// (Factotum 4.1 payload v2, OB-68202). Mirrors
    /// fixtures/mobile-api.v1/mobile-photo-intelligence-enrich.json.
    static let mobilePhotoIntelligenceEnrich = """
    {
      "received": 3,
      "updated": 2,
      "not_found": 1
    }
    """

    /// Day evidence pack for GET /api/mobile/replay/day (Factotum 4.0 W1,
    /// OB-66560). Mirrors fixtures/mobile-api.v1/mobile-replay-day.json.
    static let mobileReplayDay = """
    {"contract_version":"1.3.0","counts":{"health":1,"looki":0,"music":1,"photos":0,"timeline":0,"total":3,"visits":1,"workouts":0},"data_notes":["photos: no photo-intelligence records for this day"],"date":"2026-01-12","families":{"health":{"count":1,"items":[{"family":"health","fields":{"duration_hours":7.5,"efficiency_pct":90},"id":"sleep:2026-01-12","source":"example_sleep_nightly","summary":"Slept 7.5h at 90% efficiency","timestamp":"2026-01-12T12:00:00Z"}],"truncated":false},"looki":{"count":0,"items":[],"truncated":false},"music":{"count":1,"items":[{"family":"music","fields":{"artist":"Example Artist","plays":2,"title":"Example Song"},"id":"music:0123456789abcdef","source":"device_music","summary":"Played Example Song — Example Artist (2 plays)","timestamp":"2026-01-12T18:40:00.000Z"}],"truncated":false},"photos":{"count":0,"items":[],"truncated":false},"timeline":{"count":0,"items":[],"truncated":false},"visits":{"count":1,"items":[{"family":"visits","fields":{"locality":"Exampleton","place":"Exampleton Station"},"id":"visit:11111111-2222-3333-4444-555555555555","source":"example_device_location","summary":"Arrived at Exampleton Station","timestamp":"2026-01-12T09:15:00.000Z"}],"truncated":false},"workouts":{"count":0,"items":[],"truncated":false}},"generated_at":"2026-01-13T12:00:00.000Z","item_count":3}
    """

    /// Ask response for POST /api/mobile/replay/ask (Factotum 4.0 W1,
    /// OB-66560). Mirrors fixtures/mobile-api.v1/mobile-replay-ask.json.
    static let mobileReplayAsk = """
    {"ask":{"steps":2,"truncated":false},"citations":[{"family":"visits","fields":{"locality":"Exampleton","place":"Exampleton Station"},"id":"visit:11111111-2222-3333-4444-555555555555","source":"example_device_location","summary":"Arrived at Exampleton Station","timestamp":"2026-01-12T09:15:00.000Z"},{"family":"health","fields":{"duration_hours":7.5,"efficiency_pct":90},"id":"sleep:2026-01-12","source":"example_sleep_nightly","summary":"Slept 7.5h at 90% efficiency","timestamp":"2026-01-12T12:00:00Z"}],"contract_version":"1.3.0","generated_at":"2026-01-13T12:01:00.000Z","narrative":"You arrived at Exampleton Station in the morning [cite:visit:11111111-2222-3333-4444-555555555555]. The night before was short: 7.5 hours of sleep at 90% efficiency [cite:sleep:2026-01-12].","pack":{"counts":{"health":1,"looki":0,"music":1,"photos":0,"timeline":0,"total":3,"visits":1,"workouts":0},"data_notes":["photos: no photo-intelligence records for this day"],"item_count":3,"truncated":false,"truncated_families":[]},"question":"What did I do on this example day?","range":{"from":"2026-01-12","to":"2026-01-12"},"unresolved_citations":[]}
    """

    static let mobileOneBigThing = """
    {
      "body_age_index": {
        "components": {
          "active_energy": {
            "contribution": 0,
            "delta": 0,
            "delta_pct": 0,
            "recent": 400,
            "reference": 400,
            "status": "ok",
            "unit": "kcal"
          },
          "exercise": {
            "contribution": 0,
            "delta": 0,
            "delta_pct": 0,
            "recent": 30,
            "reference": 30,
            "status": "ok",
            "unit": "minutes"
          },
          "hrv": {
            "contribution": null,
            "delta": null,
            "delta_pct": null,
            "recent": null,
            "reference": null,
            "status": "missing",
            "unit": "ms"
          },
          "resting_heart_rate": {
            "contribution": 0,
            "delta": 0,
            "delta_pct": 0,
            "recent": 60,
            "reference": 60,
            "status": "ok",
            "unit": "bpm"
          },
          "sleep_duration": {
            "contribution": 0,
            "delta": 0,
            "delta_pct": 0,
            "recent": 8,
            "reference": 8,
            "status": "ok",
            "unit": "hours"
          }
        },
        "delta_index": -0.1,
        "direction": "steady",
        "recent_window_days": 30,
        "reference_window_days": 90,
        "unit": "index_points"
      },
      "brief_seed": {
        "fallback_paragraph": "Readiness 52/100 (high confidence) for 2026-01-12.",
        "headline_facts": [
          "Slept 7h against an 8h baseline (-1.0h) at 90% efficiency."
        ],
        "top_stress_contributor": "resting_hr_drift"
      },
      "contract_version": "1.3.0",
      "cumulative_stress": {
        "contributors": {
          "hrv_drift": {
            "detail": {},
            "score": null,
            "status": "no_data"
          },
          "resting_hr_drift": {
            "detail": {
              "delta_bpm": 0
            },
            "score": 50,
            "status": "ok"
          },
          "sleep_debt": {
            "detail": {
              "debt_hours_total": 1.0
            },
            "score": 50,
            "status": "ok"
          },
          "strain_load": {
            "detail": {
              "acwr": 1.0
            },
            "score": 50,
            "status": "ok"
          },
          "travel_disruption": {
            "detail": {
              "home_locality": "Exampleton"
            },
            "score": 20,
            "status": "ok"
          }
        },
        "days_with_data": 31,
        "index": 37,
        "window_days": 31
      },
      "data_notes": [],
      "for_date": "2026-01-12",
      "generated_at": "2026-01-13T12:00:00.000Z",
      "readiness": {
        "confidence": "high",
        "inputs": {
          "hrv": {
            "baseline": null,
            "delta": null,
            "delta_pct": null,
            "score": null,
            "status": "missing",
            "unit": "ms",
            "value": null
          },
          "resting_heart_rate": {
            "baseline": 60,
            "delta": 0,
            "delta_pct": 0,
            "score": 80,
            "status": "ok",
            "unit": "bpm",
            "value": 60
          },
          "sleep_duration": {
            "baseline": 8,
            "delta": -1,
            "delta_pct": -12.5,
            "score": 50,
            "status": "ok",
            "unit": "hours",
            "value": 7
          },
          "sleep_efficiency": {
            "baseline": 90,
            "delta": 0,
            "delta_pct": 0,
            "score": 80,
            "status": "ok",
            "unit": "percent",
            "value": 90
          },
          "strain_active_energy": {
            "baseline": 400,
            "delta": 0,
            "delta_pct": 0,
            "score": 80,
            "status": "ok",
            "unit": "kcal",
            "value": 400
          },
          "strain_exercise": {
            "baseline": 30,
            "delta": 0,
            "delta_pct": 0,
            "score": 100,
            "status": "ok",
            "unit": "minutes",
            "value": 30
          }
        },
        "score": 52
      }
    }
    """

    // MARK: - Catalog (name → JSON) for CLI / docs

    /// Every fixture name the verification command must decode.
    static var allFixtureNames: [String] {
        [
            "forge-models",
            "channel-history", "channel-history-empty",
            "health-sync", "location-sync", "visit-sync",
            "activity-sync", "activity-bulk-sync", "music-sync",
            "device-events-ack", "health-files-ack",
            "device-token-ok",
            "command-ask",
            "inbox-list", "inbox-list-empty",
            "notification-methods", "device-preferences",
            "proactive-settings", "proactive-insights", "proactive-insights-empty",
            "mobile-bootstrap-ready", "mobile-one-big-thing", "mobile-photo-intelligence", "mobile-photo-intelligence-enrich", "mobile-photo-terms",
            "mobile-replay-day", "mobile-replay-ask",
            "mobile-freshness-mixed",
        "review-cards-open", "review-cards-recent", "review-card-decide-ok",
        "review-card-decide-conflict", "review-card-decide-note-required", "mobile-bootstrap-minimal",
        ]
    }

    /// Map kebab fixture file stem → embedded JSON string.
    static func json(forFixtureName name: String) -> String? {
        switch name {
        case "forge-models": return forgeModels
        case "channel-history": return channelHistory
        case "channel-history-empty": return channelHistoryEmpty
        case "health-sync": return healthSync
        case "location-sync": return locationSync
        case "visit-sync": return visitSync
        case "activity-sync": return activitySync
        case "activity-bulk-sync": return activityBulkSync
        case "music-sync": return musicSync
        case "device-events-ack": return deviceEventsAck
        case "health-files-ack": return healthFilesAck
        case "device-token-ok": return deviceTokenOk
        case "command-ask": return commandAsk
        case "inbox-list": return inboxList
        case "inbox-list-empty": return inboxListEmpty
        case "notification-methods": return notificationMethods
        case "device-preferences": return devicePreferences
        case "proactive-settings": return proactiveSettings
        case "proactive-insights": return proactiveInsights
        case "proactive-insights-empty": return proactiveInsightsEmpty
        case "mobile-bootstrap-ready": return mobileBootstrapReady
        case "mobile-bootstrap-minimal": return mobileBootstrapMinimal
        case "review-cards-open": return reviewCardsOpen
        case "review-cards-recent": return reviewCardsRecent
        case "review-card-decide-ok": return reviewCardDecideOk
        case "review-card-decide-conflict": return reviewCardDecideConflict
        case "review-card-decide-note-required": return reviewCardDecideNoteRequired
        case "mobile-freshness-mixed": return mobileFreshnessMixed
        case "mobile-one-big-thing": return mobileOneBigThing
        case "mobile-photo-intelligence": return mobilePhotoIntelligence
        case "mobile-photo-intelligence-enrich": return mobilePhotoIntelligenceEnrich
        case "mobile-photo-terms": return mobilePhotoTerms
        case "mobile-replay-day": return mobileReplayDay
        case "mobile-replay-ask": return mobileReplayAsk
        default: return nil
        }
    }

    #if DEBUG
    /// Decode every fixture through its real model; trap on any decode failure or
    /// a filtering-rule regression. This is the app-side "fixture test".
    static func runSelfCheck() {
        do {
            let count = try verifyAll()
            assert(count == allFixtureNames.count, "expected \(allFixtureNames.count) fixtures, verified \(count)")
        } catch {
            assertionFailure("ContractFixtures.verifyAll failed: \(error)")
        }
    }
    #endif

    /// Decode every fixture through its real Codable model. Throws on the first failure.
    /// Used by DEBUG `runSelfCheck` and (via the mirrored Swift CLI script) the
    /// documented verification command.
    @discardableResult
    static func verifyAll() throws -> Int {
        let dec = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ json: String, _ label: String) throws -> T {
            guard let data = json.data(using: .utf8) else {
                throw ContractFixtureError.notUTF8(label)
            }
            do {
                return try dec.decode(T.self, from: data)
            } catch {
                throw ContractFixtureError.decodeFailed(label, String(describing: error))
            }
        }

        // Review cards (contract 1.1.0)
        let open = try decode(ReviewCardsResponse.self, reviewCardsOpen, "reviewCardsOpen")
        guard open.contractVersion == contractVersion, open.cards.count == 2 else { throw ContractFixtureError.assertion("reviewCardsOpen") }
        guard open.cards[0].requiresNote(for: "link_person"), !open.cards[0].requiresNote(for: "dismissed") else { throw ContractFixtureError.assertion("reply capture") }
        guard open.cards[1].selects.first?.options.first?.value == "p-1" else { throw ContractFixtureError.assertion("select options") }
        guard open.cards.map(\.domainRank) == [0, 1] else { throw ContractFixtureError.assertion("domain order") }
        let recent = try decode(ReviewCardsResponse.self, reviewCardsRecent, "reviewCardsRecent")
        guard recent.cards.first?.isDecided == true, recent.cards.first?.decidedOnThisPhone == true else { throw ContractFixtureError.assertion("recent decided") }
        guard try decode(ReviewDecideResponse.self, reviewCardDecideOk, "reviewCardDecideOk").card.isDecided else { throw ContractFixtureError.assertion("decide ok") }
        guard try decode(ReviewDecideConflict.self, reviewCardDecideConflict, "reviewCardDecideConflict").error == "already_decided" else { throw ContractFixtureError.assertion("decide conflict") }
        guard try decode(ReviewDecideRejected.self, reviewCardDecideNoteRequired, "reviewCardDecideNoteRequired").prompt != nil else { throw ContractFixtureError.assertion("note required") }

        // Model picker filtering (Desk parity): exactly two available text models remain.
        let models = try decode(APIClient.ForgeModelsResponse.self, forgeModels, "forgeModels")
        let pickable = models.data.filter { $0.isPickable }
        guard pickable.count == 2 else {
            throw ContractFixtureError.assertion("expected 2 pickable models, got \(pickable.count)")
        }
        guard pickable.contains(where: { $0.isLocal }) && pickable.contains(where: { !$0.isLocal }) else {
            throw ContractFixtureError.assertion("local+cloud pickable")
        }

        // History
        let history = try decode(ChannelHistoryResponse.self, channelHistory, "channelHistory")
        guard history.messages.count == 2 else { throw ContractFixtureError.assertion("history count") }
        guard history.messages.first?.role == "user" && history.messages.last?.role == "assistant" else {
            throw ContractFixtureError.assertion("history roles")
        }
        let historyEmpty = try decode(ChannelHistoryResponse.self, channelHistoryEmpty, "channelHistoryEmpty")
        guard historyEmpty.messages.isEmpty else { throw ContractFixtureError.assertion("history empty") }

        // Device sync
        let health = try decode(HealthSyncResponse.self, healthSync, "healthSync")
        guard health.synced == 3 else { throw ContractFixtureError.assertion("health synced") }
        guard try decode(LocationSyncResponse.self, locationSync, "locationSync").saved == true else {
            throw ContractFixtureError.assertion("location saved")
        }
        guard try decode(VisitSyncResponse.self, visitSync, "visitSync").saved == 2 else {
            throw ContractFixtureError.assertion("visit saved")
        }
        guard try decode(ActivitySyncResponse.self, activitySync, "activitySync").saved == true else {
            throw ContractFixtureError.assertion("activity saved")
        }
        let bulk = try decode(ActivityBulkSyncResponse.self, activityBulkSync, "activityBulkSync")
        guard bulk.saved == 4 && bulk.total == 4 else { throw ContractFixtureError.assertion("activity bulk") }
        let music = try decode(MusicSyncResponse.self, musicSync, "musicSync")
        guard music.synced == 5 else { throw ContractFixtureError.assertion("music synced") }
        let ack = try decode(IngestAck.self, deviceEventsAck, "deviceEventsAck")
        guard ack.accepted.count == 1, ack.rejected.first?.id == nil else { throw ContractFixtureError.assertion("device events ack") }
        let hfAck = try decode(IngestAck.self, healthFilesAck, "healthFilesAck")
        guard hfAck.accepted.first?.hasPrefix("hk:") == true else { throw ContractFixtureError.assertion("health files ack") }

        // Device token ack (EmptyResponse tolerates {ok:true})
        _ = try decode(EmptyResponse.self, deviceTokenOk, "deviceTokenOk")

        // Command ask
        let ask = try decode(CommandAskResponse.self, commandAsk, "commandAsk")
        guard !ask.answer.isEmpty, ask.toolCalls.count == 1, ask.readToolCount == 1 else {
            throw ContractFixtureError.assertion("command ask fields")
        }

        // Inbox
        let inbox = try decode(InboxListResponse.self, inboxList, "inboxList")
        guard inbox.items.count == 1, inbox.unreadCount == 1, inbox.items[0].isRead == false else {
            throw ContractFixtureError.assertion("inbox list")
        }
        let inboxEmpty = try decode(InboxListResponse.self, inboxListEmpty, "inboxListEmpty")
        guard inboxEmpty.items.isEmpty, inboxEmpty.total == 0 else {
            throw ContractFixtureError.assertion("inbox empty")
        }

        // Notification settings
        let methods = try decode(NotificationMethodsResponse.self, notificationMethods, "notificationMethods")
        guard methods.methods.count == 1, methods.methods[0].channel == "push" else {
            throw ContractFixtureError.assertion("notification methods")
        }
        let devices = try decode(DevicePreferencesResponse.self, devicePreferences, "devicePreferences")
        guard devices.devices.count == 1, devices.devices[0].push_preferences.notifications == true else {
            throw ContractFixtureError.assertion("device preferences")
        }

        // Proactive
        let settings = try decode(ProactiveSettingsResponse.self, proactiveSettings, "proactiveSettings")
        guard settings.settings.risk_level == "balanced" else {
            throw ContractFixtureError.assertion("proactive settings")
        }
        let insights = try decode(InsightsResponse.self, proactiveInsights, "proactiveInsights")
        guard insights.insights.count == 1, insights.insights[0].id == "insight-synthetic-1" else {
            throw ContractFixtureError.assertion("proactive insights")
        }
        let insightsEmpty = try decode(InsightsResponse.self, proactiveInsightsEmpty, "proactiveInsightsEmpty")
        guard insightsEmpty.insights.isEmpty else {
            throw ContractFixtureError.assertion("proactive insights empty")
        }

        // Mobile bootstrap (OB-52301)
        let bootReady = try decode(MobileBootstrap.self, mobileBootstrapReady, "mobileBootstrapReady")
        guard bootReady.contractVersion == contractVersion, bootReady.supportedFeatures.reviewCards else {
            throw ContractFixtureError.assertion("mobile bootstrap ready")
        }
        let bootMinimal = try decode(MobileBootstrap.self, mobileBootstrapMinimal, "mobileBootstrapMinimal")
        guard bootMinimal.supportedFeatures.reviewCards == false else {
            throw ContractFixtureError.assertion("mobile bootstrap minimal")
        }

        // Mobile freshness (OB-52302)
        let freshness = try decode(MobileFreshness.self, mobileFreshnessMixed, "mobileFreshnessMixed")

        // One Big Thing (Factotum 4.0 W3)
        let obt = try decode(MobileOneBigThing.self, mobileOneBigThing, "mobileOneBigThing")
        guard obt.contractVersion == contractVersion, obt.readiness.score == 52,
              obt.readiness.inputs.count == 6, obt.readiness.inputs["hrv"]?.status == "missing",
              obt.cumulativeStress.contributors.count == 5, obt.cumulativeStress.index == 37,
              obt.bodyAgeIndex.deltaIndex == -0.1, obt.briefSeed.headlineFacts.count == 1
        else { throw ContractFixtureError.assertion("mobileOneBigThing") }

        // Photo intelligence ingest ack (Factotum 4.0 W9)
        let photoAck = try decode(PhotoIntelligenceResponse.self, mobilePhotoIntelligence, "mobilePhotoIntelligence")
        guard photoAck.received == 2, photoAck.inserted == 2, photoAck.duplicates == 0
        else { throw ContractFixtureError.assertion("mobilePhotoIntelligence") }

        // Photo intelligence enrich ack (Factotum 4.1 payload v2)
        let enrichAck = try decode(PhotoIntelligenceEnrichResponse.self, mobilePhotoIntelligenceEnrich, "mobilePhotoIntelligenceEnrich")
        guard enrichAck.received == 3, enrichAck.updated == 2, enrichAck.notFound == 1
        else { throw ContractFixtureError.assertion("mobilePhotoIntelligenceEnrich") }

        // Life Replay day pack + ask (Factotum 4.0 W1)
        let replayDay = try decode(ReplayDayPack.self, mobileReplayDay, "mobileReplayDay")
        guard replayDay.contractVersion == contractVersion, replayDay.itemCount == 3,
              replayDay.families["visits"]?.items.first?.id == "visit:11111111-2222-3333-4444-555555555555",
              replayDay.families["health"]?.items.first?.fields["duration_hours"]?.display == "7.5"
        else { throw ContractFixtureError.assertion("mobileReplayDay") }
        let replayAsk = try decode(ReplayAskResponse.self, mobileReplayAsk, "mobileReplayAsk")
        guard replayAsk.citations.count == 2, replayAsk.unresolvedCitations.isEmpty,
              replayAsk.pack.itemCount == 3,
              replayAsk.narrative.contains("[cite:sleep:2026-01-12]")
        else { throw ContractFixtureError.assertion("mobileReplayAsk") }
        guard freshness.sources.count == 7,
              freshness.summary.overall == "error",
              freshness.sources.contains(where: { $0.appKey == "health" && $0.status == "fresh" }),
              freshness.sources.contains(where: { $0.appKey == "location" && $0.status == "stale" }),
              freshness.sources.contains(where: { $0.appKey == "motion" && $0.status == "error" }),
              freshness.sources.contains(where: { $0.appKey == "music" && $0.status == "empty" }),
              freshness.sources.contains(where: { $0.appKey == "cards" }),
              freshness.sources.contains(where: { $0.appKey == "chat" }),
              freshness.sources.contains(where: { $0.appKey == "push" }),
              freshness.platform.workerQueue.status == "ok" else {
            throw ContractFixtureError.assertion("mobile freshness mixed")
        }

        return allFixtureNames.count
    }
}

enum ContractFixtureError: Error, CustomStringConvertible {
    case notUTF8(String)
    case decodeFailed(String, String)
    case assertion(String)

    var description: String {
        switch self {
        case .notUTF8(let label): return "\(label): not utf8"
        case .decodeFailed(let label, let detail): return "\(label): decode failed — \(detail)"
        case .assertion(let msg): return "assertion: \(msg)"
        }
    }
}
