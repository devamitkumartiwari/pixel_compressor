/// Shared constants for the `targetSizeBytes` quality/resolution-stepping
/// search, used by the pure-Dart JPEG/PNG engine ([ImageEngineDart]) and the
/// web image backend. Kept numerically identical to the native Android/iOS
/// engines' own copies of these constants (`ImageEngine.kt`'s companion
/// object, `ImageEngine.swift`'s `Constants` enum) for consistent behavior
/// across every platform — those native copies can't import this Dart file
/// directly, so if these ever change, update all three by hand.
const int kTargetSizeMaxAttempts = 8;
const int kTargetSizeInitialQuality = 90;
const int kTargetSizeQualityStep = 15;
const int kTargetSizeQualityFloor = 10;
const double kTargetSizeResolutionStepFactor = 0.75;
const int kTargetSizeMinEdgePx = 200;
