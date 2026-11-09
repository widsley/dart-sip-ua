// COM-130: pure helpers for when our local SDP may be sent without waiting
// for ICE candidates.
//
// Kept side-effect free so they can be unit tested as the single source of
// truth that RTCSession actually calls.

/// Whether the offer constraints ask for an ICE restart, in the standard
/// `iceRestart` form or the legacy `mandatory.IceRestart` form.
bool isIceRestartRequested(Map<String, dynamic>? constraints) {
  if (constraints == null) {
    return false;
  }
  final dynamic mandatory = constraints['mandatory'];
  return constraints['iceRestart'] == true ||
      (mandatory is Map && mandatory['IceRestart'] == true);
}

/// Whether the local description can be used right after
/// setLocalDescription. An ICE restart starts a new gathering, so its offer
/// must wait for the new candidates even if the previous gathering completed.
bool canUseLocalDescriptionImmediately({
  required bool gatheringComplete,
  required bool iceRestart,
}) =>
    gatheringComplete && !iceRestart;

/// How long a local description waits for ICE gathering before it is used
/// as it is. The 0.5 s wait is armed only by the first candidate, so a
/// gathering that yields no candidate and never completes would otherwise
/// leave the offer or answer pending forever.
const Duration iceGatheringFallback = Duration(seconds: 5);
