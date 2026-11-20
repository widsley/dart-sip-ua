import 'dart:async';

/// CMR-1139 x16: WebSocket ping intervals that find a dead SIP connection.
///
/// A ping without a pong within one interval closes the socket (dart:io,
/// close code 1001), so the transport reconnects and the UA registers again.
/// Without it a connection left on the old network after a Wi-Fi/mobile data
/// switch counts as connected until a request times out.
class SipKeepalive {
  const SipKeepalive({
    required this.idle,
    required this.inCall,
    required this.iceProbe,
  });

  /// No call on the UA.
  final Duration idle;

  /// At least one call on the UA.
  final Duration inCall;

  /// Right after a call's ICE goes `disconnected`, for
  /// [sipKeepaliveProbeWindow], so a dead connection is known before the
  /// ICE restart is sent.
  final Duration iceProbe;

  /// x16 review: compared by value (the app compares UA settings to decide
  /// whether the UA has to start again).
  @override
  bool operator ==(Object other) =>
      other is SipKeepalive &&
      other.idle == idle &&
      other.inCall == inCall &&
      other.iceProbe == iceProbe;

  @override
  int get hashCode => Object.hash(idle, inCall, iceProbe);
}

/// How long a probe ([SipKeepalive.iceProbe]) lasts.
const Duration sipKeepaliveProbeWindow = Duration(seconds: 5);

/// The ping interval for the UA's state.
Duration sipPingInterval(SipKeepalive keepalive,
    {required bool hasCalls, required bool probing}) {
  if (probing) {
    return keepalive.iceProbe;
  }
  return hasCalls ? keepalive.inCall : keepalive.idle;
}

/// Picks the ping interval as calls start and end and ICE asks for a probe,
/// and applies it only when it changes (setting it again re-arms the ping).
class SipKeepaliveScheduler {
  SipKeepaliveScheduler(this._keepalive,
      {required void Function(Duration? interval) apply,
      Timer Function(Duration, void Function())? startTimer})
      : _apply = apply,
        _startTimer = startTimer ?? Timer.new;

  final SipKeepalive _keepalive;
  final void Function(Duration? interval) _apply;
  final Timer Function(Duration, void Function()) _startTimer;

  bool _hasCalls = false;
  Timer? _probeTimer;
  Duration? _current;

  /// The UA's calls changed (or the UA started).
  void update({required bool hasCalls}) {
    _hasCalls = hasCalls;
    _refresh();
  }

  /// Pings every [SipKeepalive.iceProbe] for [sipKeepaliveProbeWindow]; a
  /// second probe extends the window.
  void probe() {
    _probeTimer?.cancel();
    _probeTimer = _startTimer(sipKeepaliveProbeWindow, () {
      _probeTimer = null;
      _refresh();
    });
    _refresh();
  }

  /// The UA stopped.
  void stop() {
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  void _refresh() {
    final Duration next = sipPingInterval(_keepalive,
        hasCalls: _hasCalls, probing: _probeTimer != null);
    if (next == _current) {
      return;
    }
    _current = next;
    _apply(next);
  }
}
