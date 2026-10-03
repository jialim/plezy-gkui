/// Compile-time defaults for the lightweight family/projector distribution.
///
/// This is intentionally a generic profile rather than an XGIMI device-name
/// check, so the same build can serve other low-memory Android TV hardware.
/// Every setting seeded by the profile remains user-overridable.
abstract final class FamilyProjectorProfile {
  static const bool enabled = bool.fromEnvironment('FAMILY_PROJECTOR_MODE');

  /// A 1080p Android TV surface otherwise renders phone/desktop-sized 40 px
  /// controls. The dedicated projector build uses a 1.2x logical scale so
  /// those controls reach a 48 px visual target at a typical 3 m distance.
  static const double uiScale = 1.2;

  /// TV rails calculate their own height-relative scale. After [uiScale]
  /// rewrites 1080 logical pixels to 900, this baseline keeps their effective
  /// physical size enlarged instead of cancelling the root scale back out.
  static const double tvDesignHeight = 900;

  static const double focusScale = 1.06;
  static const double fullCardFocusScale = 1.07;
  static const double playerControlFocusScale = 1.18;
  static const double focusBorderWidth = 4;

  static const String buildName = String.fromEnvironment(
    'FAMILY_PROJECTOR_NAME',
    defaultValue: 'Plezy XGIMI Lite',
  );

  /// The explicit start-over action is useful only when ordinary Play would
  /// resume meaningful progress. Keep it out of standard Plezy builds.
  static bool shouldOfferPlayFromBeginning(int? viewOffsetMs) => enabled && (viewOffsetMs ?? 0) > 0;
}
