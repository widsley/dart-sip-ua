// COM-130: pure helpers for when our local SDP may be sent without waiting
// for ICE candidates.
//
// Kept free of flutter_webrtc so they can be unit tested on the Dart VM as
// the single source of truth that RTCSession actually calls.

import 'dart:async';

import 'timers.dart';

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

/// Settles a local description once, by whichever comes first: [ready]
/// (gathering complete, or the short wait after the first candidate) or the
/// backstop armed by [armFallback]. [onFallback] runs only when the backstop
/// is what settles it, so the caller can log it.
class LocalDescriptionSettler {
  LocalDescriptionSettler({
    required bool Function() canSettle,
    required Future<void> Function() settle,
    required void Function() onFallback,
    Duration fallbackAfter = iceGatheringFallback,
  })  : _canSettle = canSettle,
        _settle = settle,
        _onFallback = onFallback,
        _fallbackAfter = fallbackAfter;

  final bool Function() _canSettle;
  final Future<void> Function() _settle;
  final void Function() _onFallback;
  final Duration _fallbackAfter;
  Timer? _fallback;
  bool _settled = false;

  Future<void> ready() => _ready(byFallback: false);

  void armFallback() {
    clearTimeout(_fallback);
    _fallback = setTimeout(
        () => _ready(byFallback: true), _fallbackAfter.inMilliseconds);
  }

  Future<void> _ready({required bool byFallback}) async {
    clearTimeout(_fallback);
    if (_settled || !_canSettle()) {
      return;
    }
    _settled = true;
    if (byFallback) {
      _onFallback();
    }
    await _settle();
  }
}
