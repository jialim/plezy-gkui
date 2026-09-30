/// Compile-time defaults for the lightweight family/projector distribution.
///
/// This is intentionally a generic profile rather than an XGIMI device-name
/// check, so the same build can serve other low-memory Android TV hardware.
/// Every setting seeded by the profile remains user-overridable.
abstract final class FamilyProjectorProfile {
  static const bool enabled = bool.fromEnvironment('FAMILY_PROJECTOR_MODE');

  static const String buildName = String.fromEnvironment(
    'FAMILY_PROJECTOR_NAME',
    defaultValue: 'Plezy XGIMI Lite',
  );
}
