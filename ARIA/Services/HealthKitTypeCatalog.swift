import Foundation
import HealthKit

// MARK: - Type catalog

extension HealthKitService {

    struct TypeCatalog {
        let quantityUnits: [HKQuantityType: HKUnit]
        let categoryTypes: [HKCategoryType]
        let workoutType: HKWorkoutType
        /// Non-quantity/category sample types mapped by special cases in mapToRaw.
        let extraSampleTypes: [HKSampleType]

        var allSampleTypes: Set<HKSampleType> {
            var set = Set<HKSampleType>()
            for type in quantityUnits.keys { set.insert(type) }
            for type in categoryTypes { set.insert(type) }
            set.insert(workoutType)
            for type in extraSampleTypes { set.insert(type) }
            return set
        }
    }

    /// Distinct candidate units spanning every dimension we read, used as the
    /// crash-safe fallback when a quantity is not compatible with its mapped
    /// canonical unit. Order matters only in that the first compatible one wins.
    nonisolated static let fallbackUnits: [HKUnit] = [
        .count(),
        HKUnit.count().unitDivided(by: .minute()),           // per-minute rates
        HKUnit.secondUnit(with: .milli),                     // ms
        .minute(),
        .second(),
        .kilocalorie(),
        .meter(),
        HKUnit.meter().unitDivided(by: .second()),           // m/s
        .mile(),
        .percent(),
        .degreeCelsius(),
        .millimeterOfMercury(),
        HKUnit(from: "mg/dL"),                               // glucose (mass/vol, US)
        HKUnit.moleUnit(with: .milli, molarMass: HKUnitMolarMassBloodGlucose)
            .unitDivided(by: .liter()),                      // glucose (molar, mmol/L)
        HKUnit.literUnit(with: .milli),                      // mL
        HKUnit.gramUnit(with: .kilo),                        // kg
        .gram(),
        HKUnit.gramUnit(with: .milli),                       // mg
        HKUnit.gramUnit(with: .micro),                       // µg
        .watt(),
        HKUnit.decibelAWeightedSoundPressureLevel(),         // dBASPL
        HKUnit.siemenUnit(with: .micro),                     // µS (electrodermal)
        HKUnit.internationalUnit(),
        HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())), // VO2 mL/(kg·min)
    ]

    nonisolated static func buildCatalog() -> TypeCatalog {
        var q: [HKQuantityType: HKUnit] = [:]
        func add(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) {
            q[HKQuantityType(id)] = unit
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let ms = HKUnit.secondUnit(with: .milli)
        let kcal = HKUnit.kilocalorie()
        let meter = HKUnit.meter()
        let mps = HKUnit.meter().unitDivided(by: .second())
        let kg = HKUnit.gramUnit(with: .kilo)
        let mg = HKUnit.gramUnit(with: .milli)
        let mcg = HKUnit.gramUnit(with: .micro)
        let gram = HKUnit.gram()
        let mL = HKUnit.literUnit(with: .milli)
        let percent = HKUnit.percent()
        let count = HKUnit.count()
        let minute = HKUnit.minute()
        let dbaspl = HKUnit.decibelAWeightedSoundPressureLevel()
        let vo2Unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        // Activity & movement
        add(.stepCount, count)
        add(.distanceWalkingRunning, meter)
        add(.distanceCycling, meter)
        add(.distanceSwimming, meter)
        add(.distanceWheelchair, meter)
        add(.distanceDownhillSnowSports, meter)
        add(.basalEnergyBurned, kcal)
        add(.activeEnergyBurned, kcal)
        add(.flightsClimbed, count)
        add(.appleExerciseTime, minute)
        add(.appleStandTime, minute)
        add(.appleMoveTime, minute)
        add(.pushCount, count)
        add(.swimmingStrokeCount, count)
        add(.nikeFuel, count)
        add(.numberOfTimesFallen, count)
        add(.physicalEffort, kcal.unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour()))) // kcal/(kg·hr) MET-like
        add(.walkingSpeed, mps)
        add(.walkingStepLength, meter)
        add(.walkingAsymmetryPercentage, percent)
        add(.walkingDoubleSupportPercentage, percent)
        add(.sixMinuteWalkTestDistance, meter)
        add(.stairAscentSpeed, mps)
        add(.stairDescentSpeed, mps)
        add(.appleWalkingSteadiness, percent)
        add(.runningSpeed, mps)
        add(.runningPower, HKUnit.watt())
        add(.runningStrideLength, meter)
        add(.runningVerticalOscillation, meter)
        add(.runningGroundContactTime, ms)
        add(.cyclingSpeed, mps)
        add(.cyclingPower, HKUnit.watt())
        add(.cyclingCadence, HKUnit.count().unitDivided(by: .minute()))
        add(.cyclingFunctionalThresholdPower, HKUnit.watt())
        add(.underwaterDepth, meter)
        // OB-54163: workout-effort scores were never in the catalog (never permissioned).
        // Both are iOS 18.0+ and their canonical unit is appleEffortScore
        // (HKTypeIdentifiers.h: "// appleEffortScore, Discrete (Arithmetic)").
        if #available(iOS 18.0, *) {
            add(.estimatedWorkoutEffortScore, HKUnit.appleEffortScore())
            add(.workoutEffortScore, HKUnit.appleEffortScore())
        }

        // Heart & vitals
        add(.heartRate, bpm)
        add(.restingHeartRate, bpm)
        add(.walkingHeartRateAverage, bpm)
        add(.heartRateVariabilitySDNN, ms)
        add(.heartRateRecoveryOneMinute, bpm)
        add(.atrialFibrillationBurden, percent)
        add(.oxygenSaturation, percent)
        add(.bodyTemperature, HKUnit.degreeCelsius())
        add(.basalBodyTemperature, HKUnit.degreeCelsius())
        add(.appleSleepingWristTemperature, HKUnit.degreeCelsius())
        add(.waterTemperature, HKUnit.degreeCelsius())
        add(.bloodPressureSystolic, HKUnit.millimeterOfMercury())
        add(.bloodPressureDiastolic, HKUnit.millimeterOfMercury())
        add(.respiratoryRate, bpm)
        // OB-54163: sleep-apnea screening stream (count of disturbances).
        if #available(iOS 18.0, *) {
            add(.appleSleepingBreathingDisturbances, count)
        }
        add(.vo2Max, vo2Unit)
        add(.peripheralPerfusionIndex, percent)

        // Body measurements
        add(.bodyMass, kg)
        add(.bodyMassIndex, count)
        add(.bodyFatPercentage, percent)
        add(.leanBodyMass, kg)
        add(.height, meter)
        add(.waistCircumference, meter)

        // Metabolic / lab
        add(.bloodGlucose, HKUnit(from: "mg/dL"))
        add(.bloodAlcoholContent, percent)
        add(.insulinDelivery, HKUnit.internationalUnit())
        add(.numberOfAlcoholicBeverages, count)

        // Respiratory & environment
        add(.forcedVitalCapacity, HKUnit.liter())
        add(.forcedExpiratoryVolume1, HKUnit.liter())
        add(.peakExpiratoryFlowRate, HKUnit.liter().unitDivided(by: .minute()))
        add(.inhalerUsage, count)
        add(.environmentalAudioExposure, dbaspl)
        add(.headphoneAudioExposure, dbaspl)
        add(.environmentalSoundReduction, dbaspl)
        add(.uvExposure, count)
        add(.timeInDaylight, minute)
        add(.electrodermalActivity, HKUnit.siemenUnit(with: .micro))

        // Nutrition — energy/macros
        add(.dietaryEnergyConsumed, kcal)
        add(.dietaryCarbohydrates, gram)
        add(.dietaryFiber, gram)
        add(.dietarySugar, gram)
        add(.dietaryFatTotal, gram)
        add(.dietaryFatMonounsaturated, gram)
        add(.dietaryFatPolyunsaturated, gram)
        add(.dietaryFatSaturated, gram)
        add(.dietaryCholesterol, mg)
        add(.dietaryProtein, gram)
        add(.dietaryWater, mL)
        add(.dietaryCaffeine, mg)
        // Nutrition — minerals
        add(.dietarySodium, mg)
        add(.dietaryPotassium, mg)
        add(.dietaryCalcium, mg)
        add(.dietaryIron, mg)
        add(.dietaryMagnesium, mg)
        add(.dietaryPhosphorus, mg)
        add(.dietaryZinc, mg)
        add(.dietaryChloride, mg)
        add(.dietaryChromium, mcg)
        add(.dietaryCopper, mg)
        add(.dietaryIodine, mcg)
        add(.dietaryManganese, mg)
        add(.dietaryMolybdenum, mcg)
        add(.dietarySelenium, mcg)
        // Nutrition — vitamins
        add(.dietaryVitaminA, mcg)
        add(.dietaryVitaminB6, mg)
        add(.dietaryVitaminB12, mcg)
        add(.dietaryVitaminC, mg)
        add(.dietaryVitaminD, mcg)
        add(.dietaryVitaminE, mg)
        add(.dietaryVitaminK, mcg)
        add(.dietaryThiamin, mg)
        add(.dietaryRiboflavin, mg)
        add(.dietaryNiacin, mg)
        add(.dietaryFolate, mcg)
        add(.dietaryBiotin, mcg)
        add(.dietaryPantothenicAcid, mg)

        // Category types — high-signal / commonly-populated set. The full
        // reproductive-health + long-tail symptom identifiers are intentionally
        // deferred (the export.xml import already captures them losslessly);
        // add them here as they start streaming.
        var categories: [HKCategoryType] = [
            HKCategoryType(.sleepAnalysis),
            HKCategoryType(.appleStandHour),
            HKCategoryType(.mindfulSession),
            HKCategoryType(.highHeartRateEvent),
            HKCategoryType(.lowHeartRateEvent),
            HKCategoryType(.irregularHeartRhythmEvent),
            HKCategoryType(.environmentalAudioExposureEvent),
            HKCategoryType(.headphoneAudioExposureEvent),
            HKCategoryType(.lowCardioFitnessEvent),
            HKCategoryType(.appleWalkingSteadinessEvent),
            HKCategoryType(.handwashingEvent),
            HKCategoryType(.toothbrushingEvent),
            // Common symptoms (Apple Watch / manual)
            HKCategoryType(.headache),
            HKCategoryType(.nausea),
            HKCategoryType(.fatigue),
            HKCategoryType(.coughing),
            HKCategoryType(.fever),
            HKCategoryType(.chills),
            HKCategoryType(.dizziness),
            HKCategoryType(.shortnessOfBreath),
            HKCategoryType(.soreThroat),
            HKCategoryType(.runnyNose),
            HKCategoryType(.sinusCongestion),
        ]

        if #available(iOS 26.2, *) {
            categories.append(HKCategoryType(.hypertensionEvent))
        }

        return TypeCatalog(
            quantityUnits: q,
            categoryTypes: categories,
            workoutType: HKObjectType.workoutType(),
            extraSampleTypes: [HKSampleType.stateOfMindType(), HKObjectType.medicationDoseEventType()]
        )
    }
}

