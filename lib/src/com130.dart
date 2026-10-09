// COM-130: pure decision helpers for audio-interruption handling.
//
// These are kept side-effect free so they can be unit tested as the single
// source of truth that RTCSession actually calls (rather than tests
// re-implementing the branching).

/// Action to take when an audio interruption ends
/// (RTCSession.setAudioInterrupted(false)).
class ResumeAfterInterruption {
  const ResumeAfterInterruption({
    required this.unhold,
    required this.iceRestart,
  });

  /// Release the local hold that was auto-applied during the interruption.
  final bool unhold;

  /// Recover the media path via a single ICE-restart re-INVITE.
  final bool iceRestart;
}

/// Decide what to do when an audio interruption ends.
///
/// - If the session is terminated/canceled: do nothing.
/// - If we were holding (auto-hold during the interruption): un-hold.
/// - Restart ICE when we just un-held or the ICE state is failed/disconnected,
///   unless a restart is already in progress.
ResumeAfterInterruption resumeAfterInterruptionDecision({
  required bool terminated,
  required bool localHold,
  required bool iceFailedOrDisconnected,
  required bool isAttemptingIceRestart,
}) {
  if (terminated) {
    return const ResumeAfterInterruption(unhold: false, iceRestart: false);
  }
  final bool wasHeld = localHold;
  final bool restart =
      (wasHeld || iceFailedOrDisconnected) && !isAttemptingIceRestart;
  return ResumeAfterInterruption(unhold: wasHeld, iceRestart: restart);
}

/// Whether an ICE `Failed` should tear the call down immediately.
///
/// During an audio interruption (e.g. a native call) the failure is transient,
/// so the teardown is suppressed and recovery is attempted on resume.
bool shouldTeardownOnIceFailed({required bool audioInterrupted}) =>
    !audioInterrupted;
