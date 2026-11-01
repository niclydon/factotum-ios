# HealthKit enrichment spec

**Status:** Deferred in the original project. Not blocking anything.
This is the generalized public form of the spec: the HealthKit
mechanism is unchanged; backend table and migration names from the
author's deployment are replaced with descriptive names, and no
example payload in this document is real health data.

---

## Why this exists

The app is a live producer for HealthKit data into a personal backend,
but its `HealthKitService.swift` extracts only the most basic
per-workout fields (type, start, end, duration, calories). A separate
fitness platform currently provides the rich workout enrichment
(distance, heart rate, GPS, splits) by reading from HealthKit,
computing detailed metrics, and feeding them back through its own API
into the backend's activities pipeline.

If you ever want to drop that dependency, or if you log manual
workouts that never reach the fitness platform and want them richly
described, the app would need to extract more from HealthKit directly.
This spec documents what is missing and what it would take to close
the gap.

## Current behavior

In `ARIA/Services/HealthKitService.swift`, `queryWorkoutRecords(start:end:)`
builds each workout entry from five fields, plus calories when present:

```swift
for workout in workouts {
    let durationMinutes = round(workout.duration / 60.0)
    let typeName = Self.workoutName(workout.workoutActivityType)
    let startTime = Self.iso8601Formatter.string(from: workout.startDate)
    let endTime = Self.iso8601Formatter.string(from: workout.endDate)

    var entry: [String: HealthValue] = [
        "type": .text(typeName),
        "duration_minutes": .number(durationMinutes),
        "start_time": .text(startTime),
        "end_time": .text(endTime),
    ]
    if let energy = workout.totalEnergyBurned {
        entry["calories"] = .number(round(energy.doubleValue(for: .kilocalorie())))
    }

    workoutEntries.append(entry)
}
```

## What HealthKit actually exposes

`HKWorkout` is the entrypoint, but the rich data hangs off it via
separate queries:

### Direct properties on HKWorkout

Already on the workout object, just not extracted:

- `workout.totalDistance` — HKQuantity, available as miles or km
- `workout.totalSwimmingStrokeCount` — for swims
- `workout.totalFlightsClimbed` — stairs
- `workout.totalEnergyBurned` — already extracted
- `workout.duration` — already extracted
- `workout.workoutEvents` — pause/resume events, lap markers, segment markers
- `workout.metadata` — HK metadata dict (may include `HKIndoorWorkout`, `HKWeatherTemperature`, `HKWeatherHumidity`, `HKAverageMETs`, etc.)
- `workout.sourceRevision` — which app/device created the workout

These are **synchronous** reads, no extra HealthKit query needed.

### Heart rate samples during the workout

Requires a separate `HKSampleQuery` scoped to the workout's time window:

```swift
let hrPredicate = HKQuery.predicateForSamples(
    withStart: workout.startDate,
    end: workout.endDate,
    options: .strictStartDate
)
let hrQuery = HKSampleQuery(
    sampleType: HKQuantityType(.heartRate),
    predicate: hrPredicate,
    limit: HKObjectQueryNoLimit,
    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
) { _, samples, _ in
    // Compute avg, max, min from samples
    // Or downsample to e.g. one reading per 30 seconds for streams
}
```

### GPS route (HKWorkoutRoute)

HealthKit stores GPS routes as a separate `HKWorkoutRouteQuery`:

```swift
let routeQuery = HKAnchoredObjectQuery(
    type: HKSeriesType.workoutRoute(),
    predicate: HKQuery.predicateForObjects(from: workout),
    anchor: nil,
    limit: HKObjectQueryNoLimit
) { _, samples, _, _, _ in
    guard let route = samples?.first as? HKWorkoutRoute else { return }
    let locationQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, _ in
        // CLLocation array — full GPS polyline with timestamps and altitude
    }
    healthStore.execute(locationQuery)
}
```

A `CLLocation` includes lat, lng, altitude, horizontal/vertical
accuracy, course, speed, and timestamp. Encoding to a polyline
(Google's polyline format) is straightforward.

### Other samples during the workout window

By predicating on `workout.startDate..workout.endDate`, you can pull
during-workout samples for cadence, speed, power, VO2 max, and
per-second energy. Each is a separate `HKSampleQuery`; they can run
in parallel.

## Recommended extraction tiers

### Tier 1 (cheap, immediate value): direct HKWorkout properties

Add to the existing `queryWorkoutRecords` loop:

```swift
if let distance = workout.totalDistance {
    entry["distance_meters"] = .number(distance.doubleValue(for: .meter()))
}
if let strokes = workout.totalSwimmingStrokeCount {
    entry["swim_strokes"] = .number(strokes.doubleValue(for: .count()))
}
if let flights = workout.totalFlightsClimbed {
    entry["flights_climbed"] = .number(flights.doubleValue(for: .count()))
}
if let metadata = workout.metadata {
    entry["hk_metadata"] = .json(metadata)  // includes weather, indoor flag, METs
}
entry["source_app"] = .text(workout.sourceRevision.source.name)
entry["source_bundle"] = .text(workout.sourceRevision.source.bundleIdentifier)
```

Effort: ~30 minutes including testing. No new query paths. This alone
closes a significant chunk of the enrichment gap.

### Tier 2 (medium): HR samples during workout

Add a helper `queryHeartRateSamples(during:)` that returns avg/max/min
plus an optional downsampled stream (e.g. one point per 30 seconds).
Effort: ~2 hours including testing across workout types.

### Tier 3 (heavy): GPS route extraction

`HKWorkoutRouteQuery` is async and paginated, and only fires for
outdoor workouts that recorded location: detect the route, accumulate
`CLLocation` arrays, encode to polyline, compute splits client-side
(or send raw points and let the server compute). Effort: ~1 day.
Recommended only if you decide to drop the external enrichment source.

## Server-side implications

The current `/api/health-data` handler writes the entire workout
payload into the raw health table's metadata column, so new fields
from Tier 1/2/3 land there with no schema change. To make them
queryable in an aggregated workouts view, extend that view to extract
the new metadata paths as columns — one expression per field. If
extracting GPS polylines (Tier 3), consider promoting the polyline to
a dedicated column on a dedicated workouts table: storing a ~5KB
polyline in a JSON metadata column on every daily aggregate row would
bloat the table.

## Decision: ship Tier 1 only?

Tier 1 is a clear win: cheap, closes most of the gap for fields that
are *already on the HKWorkout object*, and requires no new query
patterns. Tier 2 and Tier 3 only matter if you want to remove the
external enrichment dependency; keeping both sources and joining them
in the aggregated view gives you the union today — no urgency.

## Files to change

- `ARIA/Services/HealthKitService.swift` — extend `queryWorkoutRecords`
- Backend: extend the aggregated workouts view (one expression per new field)
