import Foundation

/// Pure shaping rules for HealthKit samples that don't fit quantity/category/workout.
/// Kept free of HealthKit types so the DEBUG self-check can exercise them.
enum HealthRecordMapping {
    /// The raw-health identity key ignores metadata, so two medications logged at the
    /// same instant with the same dose would collide. Suffixing the concept id keeps them
    /// distinct; downstream still matches `record_type LIKE 'HKMedicationDoseEvent%'`.
    static func medicationRecordType(conceptId: String) -> String {
        "HKMedicationDoseEvent:\(conceptId)"
    }

    /// HKStateOfMind labels/associations are ObjC enums without stable names; store raw
    /// values (comma-joined) plus kind and valence classification.
    static func stateOfMindMetadata(kindRaw: Int, valenceClassificationRaw: Int, labelsRaw: [Int], associationsRaw: [Int]) -> [String: HealthValue] {
        [
            "kind_raw": .number(Double(kindRaw)),
            "valence_classification_raw": .number(Double(valenceClassificationRaw)),
            "labels_raw": .text(labelsRaw.map(String.init).joined(separator: ",")),
            "associations_raw": .text(associationsRaw.map(String.init).joined(separator: ",")),
        ]
    }

    static func medicationMetadata(name: String?, logStatusRaw: Int, scheduledDate: Date?, scheduledDose: Double?) -> [String: HealthValue] {
        var m: [String: HealthValue] = ["log_status_raw": .number(Double(logStatusRaw))]
        if let name, !name.isEmpty { m["medication_name"] = .text(name) }
        if let scheduledDate { m["scheduled_date"] = .text(DeviceEventFactory.string(from: scheduledDate)) }
        if let scheduledDose { m["scheduled_dose"] = .number(scheduledDose) }
        return m
    }

    #if DEBUG
    static func runSelfCheck() {
        assert(medicationRecordType(conceptId: "rxnorm:197361") == "HKMedicationDoseEvent:rxnorm:197361")
        assert(medicationRecordType(conceptId: "a") != medicationRecordType(conceptId: "b"), "two meds at one instant stay distinct")
        let som = stateOfMindMetadata(kindRaw: 1, valenceClassificationRaw: 5, labelsRaw: [12, 3], associationsRaw: [])
        assert(som["labels_raw"] == .text("12,3") && som["associations_raw"] == .text(""))
        let med = medicationMetadata(name: "Vitamin D", logStatusRaw: 4, scheduledDate: nil, scheduledDose: 1)
        assert(med["medication_name"] == .text("Vitamin D") && med["scheduled_date"] == nil && med["scheduled_dose"] == .number(1))
        assert(medicationMetadata(name: "", logStatusRaw: 1, scheduledDate: nil, scheduledDose: nil)["medication_name"] == nil)
    }
    #endif
}
