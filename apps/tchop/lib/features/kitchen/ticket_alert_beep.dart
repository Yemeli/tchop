import 'package:flutter/services.dart';

/// New-ticket alert hook for the kitchen ticket board.
///
/// Kitchen hands are busy and wet — a new "Nouveau" ticket must announce
/// itself. [beep] fires the haptic immediately; the audible chime is a
/// TODO until an audio asset is bundled.
///
/// Reduced-motion / lite mode silence the alert: the kitchen board sets
/// [quiet] from the device [AppSettings] (via `AppSettingsScope`) so the
/// data-layer [KitchenOrderSync] never needs a BuildContext — the flag is
/// the documented bridge between the settings UI and the sync path.
///
/// TODO(audio): add `assets/audio/ticket_chime.mp3` (short, subtle, <1s),
/// register it in pubspec `assets:`, and play it here with `just_audio`
/// (or `audioplayers`) — keeping the haptic as a fallback so a missing
/// asset can never break the alert path.
abstract final class TicketAlertBeep {
  /// Global kill-switch, set by the ticket board from the device's
  /// "Réduire les animations" / "Mode allégé" settings.
  static bool quiet = false;

  /// Subtle new-ticket alert: haptic now, sound when the asset lands.
  /// Silent when [quiet] (or [quietOverride]) is true.
  static void beep({bool quietOverride = false}) {
    if (quiet || quietOverride) return;
    HapticFeedback.mediumImpact();
    // TODO(audio): play the ticket chime asset — see the file-level TODO.
  }
}
