import Foundation
import HealthKit

/// Sample -> raw-row mapping, split out of HealthKitService.swift
/// (1,117 lines at 3.3.0) with no behavior change (3.4.0).
extension HealthKitService {

    // MARK: - Sample → raw mapping

    /// Map one HealthKit sample to the raw POST shape. Returns nil for samples we
    /// cannot safely read (a quantity whose value is not compatible with any
    /// known unit — guarded so an unexpected type never CRASHES via a bad
    /// doubleValue(for:) call).
    nonisolated static func mapToRaw(_ sample: HKSample, sampleType: HKSampleType) -> RawHealthSample? {
        let start = iso8601Formatter.string(from: sample.startDate)
        let end = iso8601Formatter.string(from: sample.endDate)
        let source = sample.sourceRevision.source.name
        let device = sample.device?.name

        if let quantitySample = sample as? HKQuantitySample {
            let preferred = catalog.quantityUnits[quantitySample.quantityType]
            guard let (value, unitString) = readQuantity(quantitySample.quantity, preferred: preferred) else {
                return nil
            }
            return RawHealthSample(
                recordType: sampleType.identifier,
                startDate: start,
                endDate: end,
                value: value,
                unit: unitString,
                sourceName: source,
                device: device,
                metadata: nil
            )
        }

        if let categorySample = sample as? HKCategorySample {
            // Raw: store the category rawValue as the numeric value (interpretable
            // together with record_type downstream); unit is not applicable.
            return RawHealthSample(
                recordType: sampleType.identifier,
                startDate: start,
                endDate: end,
                value: Double(categorySample.value),
                unit: nil,
                sourceName: source,
                device: device,
                metadata: nil
            )
        }

        if let workout = sample as? HKWorkout {
            var metadata: [String: HealthValue] = [
                "activity_type": .text(workoutName(workout.workoutActivityType)),
                "activity_type_raw": .number(Double(workout.workoutActivityType.rawValue)),
            ]
            if let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                metadata["energy_kcal"] = .number(energy)
            }
            if let distance = workout.totalDistance?.doubleValue(for: .meter()) {
                metadata["distance_m"] = .number(distance)
            }
            return RawHealthSample(
                recordType: sampleType.identifier,
                startDate: start,
                endDate: end,
                value: workout.duration,   // seconds
                unit: "s",
                sourceName: source,
                device: device,
                metadata: metadata
            )
        }

        if let mood = sample as? HKStateOfMind {
            return RawHealthSample(
                recordType: sampleType.identifier,
                startDate: start,
                endDate: end,
                value: mood.valence,
                unit: nil,
                sourceName: source,
                device: device,
                metadata: HealthRecordMapping.stateOfMindMetadata(
                    kindRaw: mood.kind.rawValue,
                    valenceClassificationRaw: mood.valenceClassification.rawValue,
                    labelsRaw: mood.labels.map(\.rawValue),
                    associationsRaw: mood.associations.map(\.rawValue)))
        }

        if let dose = sample as? HKMedicationDoseEvent {
            let key = conceptKey(dose.medicationConceptIdentifier)
            let name = medicationNames.withLock { $0[key] }
            return RawHealthSample(
                recordType: HealthRecordMapping.medicationRecordType(conceptId: key),
                startDate: start,
                endDate: end,
                value: dose.doseQuantity,
                unit: dose.unit.unitString,
                sourceName: source,
                device: device,
                metadata: HealthRecordMapping.medicationMetadata(
                    name: name,
                    logStatusRaw: dose.logStatus.rawValue,
                    scheduledDate: dose.scheduledDate,
                    scheduledDose: dose.scheduledDoseQuantity))
        }

        return nil
    }

    /// Read a quantity into (value, unitString) WITHOUT ever crashing. HealthKit's
    /// `doubleValue(for:)` throws an uncatchable ObjC exception if the unit is
    /// incompatible, so every read is gated by `is(compatibleWith:)`. Falls back
    /// to any compatible unit from the global candidate set if the preferred
    /// canonical unit is missing/wrong — the chosen unit's string is recorded
    /// alongside the value, so the reading stays interpretable.
    nonisolated static func readQuantity(_ quantity: HKQuantity, preferred: HKUnit?) -> (Double, String)? {
        if let preferred, quantity.is(compatibleWith: preferred) {
            return (quantity.doubleValue(for: preferred), preferred.unitString)
        }
        for candidate in fallbackUnits where quantity.is(compatibleWith: candidate) {
            return (quantity.doubleValue(for: candidate), candidate.unitString)
        }
        return nil
    }


    nonisolated static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .functionalStrengthTraining: "Strength Training"
        case .traditionalStrengthTraining: "Strength Training"
        case .coreTraining: "Core Training"
        case .highIntensityIntervalTraining: "HIIT"
        case .dance: "Dance"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .stairClimbing: "Stair Climbing"
        case .pilates: "Pilates"
        case .tennis: "Tennis"
        case .basketball: "Basketball"
        case .soccer: "Soccer"
        case .golf: "Golf"
        case .cooldown: "Cooldown"
        case .mixedCardio: "Mixed Cardio"
        default: "Other"
        }
    }
}
