import 'dart:async';

/// CMR-1139 x9: how a call recovers its media after a network drop or switch.
enum IceRecoveryPolicy {
  /// Long-standing behaviour: one ICE restart 20 s after `disconnected`, the
  /// call ends on `failed`, and a restart sent while the SIP transport is down
  /// ends the call. RTCSession keeps its existing code for this policy.
  standard,

  /// Restart 4 s after `disconnected` and once on `failed`, after the SIP
  /// transport is back. Handled by [IceRecoveryController].
  fast,
}

/// Time in `disconnected` before the fast policy restarts ICE.
const Duration fastIceRestartDelay = Duration(seconds: 4);

/// How long a restart waits for the SIP transport before the call ends.
const Duration iceTransportWaitLimit = Duration(seconds: 15);

/// How long ICE may take to reconnect after a restart was sent.
const Duration iceRecoveryLimit = Duration(seconds: 15);

/// Retry delay when the restart re-INVITE could not start (another re-INVITE
/// was pending) and ICE is still `disconnected`.
const Duration iceRestartRetryDelay = Duration(seconds: 1);

/// How often a waiting restart asks the SIP transport to reconnect (x13).
const Duration iceTransportReconnectInterval = Duration(seconds: 2);

/// How often the SIP transport is checked while a restart waits for it.
const Duration iceTransportPollInterval = Duration(milliseconds: 250);

/// ICE connection states the controller reacts to (flutter_webrtc free).
enum IceConnState { checking, connected, completed, disconnected, failed }

/// Why the controller ended the call.
enum IceRecoveryEnd { iceFailed, iceNotRecovered, transportNotBack }

/// Offer constraints for one ICE-restart re-INVITE. [base] is copied, so later
/// re-INVITEs (hold, unhold) do not restart ICE again.
Map<String, dynamic> iceRestartOfferConstraints(Map<String, dynamic>? base) {
  final Map<String, dynamic> mandatory = <String, dynamic>{};
  final dynamic baseMandatory = base?['mandatory'];
  if (baseMandatory is Map) {
    baseMandatory.forEach((dynamic key, dynamic value) {
      mandatory['$key'] = value;
    });
  }
  mandatory['IceRestart'] = true;
  final dynamic baseOptional = base?['optional'];
  return <String, dynamic>{
    ...?base,
    'mandatory': mandatory,
    'optional':
        baseOptional is List ? List<dynamic>.from(baseOptional) : <dynamic>[],
  };
}

/// Options for `RTCSession.renegotiate` that send an audio-only ICE restart
/// (not the video-upgrade re-INVITE).
Map<String, dynamic> iceRestartRenegotiateOptions(Map<String, dynamic>? base) =>
    <String, dynamic>{
      'rtcOfferConstraints': iceRestartOfferConstraints(base),
      'mediaConstraints': <String, dynamic>{'audio': true, 'video': false},
    };

/// Writes one ICE line to the device log in every build mode. State names and
/// decisions only; no candidates or addresses.
void iceLog(String message) {
  print('[ICE] $message');
}

/// CMR-1139 x9: ICE recovery for [IceRecoveryPolicy.fast].
///
/// RTCSession forwards ICE states and supplies the actions; this class owns
/// the timers (restart delay, SIP transport wait, recovery limit).
class IceRecoveryController {
  IceRecoveryController({
    required bool Function() isSessionOver,
    required bool Function() isAudioInterrupted,
    required bool Function() isTransportConnected,
    required bool Function() sendIceRestart,
    required void Function(IceRecoveryEnd reason) endCall,
    required bool Function() requestTransportReconnect,
    void Function(String message) log = iceLog,
    Timer Function(Duration, void Function())? startTimer,
    Timer Function(Duration, void Function(Timer))? startPeriodicTimer,
  })  : _isSessionOver = isSessionOver,
        _isAudioInterrupted = isAudioInterrupted,
        _isTransportConnected = isTransportConnected,
        _sendIceRestart = sendIceRestart,
        _endCall = endCall,
        _requestTransportReconnect = requestTransportReconnect,
        _log = log,
        _startTimer = startTimer ?? Timer.new,
        _startPeriodicTimer = startPeriodicTimer ?? Timer.periodic;

  final bool Function() _isSessionOver;
  final bool Function() _isAudioInterrupted;
  final bool Function() _isTransportConnected;
  final bool Function() _sendIceRestart;
  final void Function(IceRecoveryEnd reason) _endCall;
  final bool Function() _requestTransportReconnect;
  final void Function(String message) _log;
  final Timer Function(Duration, void Function()) _startTimer;
  final Timer Function(Duration, void Function(Timer)) _startPeriodicTimer;

  IceConnState? _last;
  Timer? _disconnectTimer;
  Timer? _transportWait;
  Timer? _recoveryDeadline;
  bool _restarting = false;
  bool _disposed = false;

  /// A restart is waiting for the transport or for ICE to reconnect.
  bool get restarting => _restarting;

  /// Reacts to a new ICE connection state.
  void onIceState(IceConnState state) {
    if (_disposed) {
      return;
    }
    _last = state;
    if (state == IceConnState.disconnected) {
      _onDisconnected();
    } else if (state == IceConnState.failed) {
      _onFailed();
    } else if (state == IceConnState.connected ||
        state == IceConnState.completed) {
      final bool recovering = _restarting || _disconnectTimer != null;
      _resetEpisode();
      _log(recovering ? '${state.name}, recovered' : state.name);
    } else {
      _log(state.name);
    }
  }

  /// Restarts ICE now unless a restart is already in progress (also used when
  /// an audio interruption ends).
  void restartNow(String reason) {
    if (_disposed || _isSessionOver()) {
      return;
    }
    if (_restarting) {
      _log('ICE restart already in progress ($reason)');
      return;
    }
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _restarting = true;
    if (_isTransportConnected()) {
      _send(reason);
    } else {
      _log('ICE restart ($reason): waiting for the SIP transport, '
          'up to ${iceTransportWaitLimit.inSeconds} s');
      _waitForTransport(reason);
    }
  }

  /// Cancels every timer; called when the session ends.
  void dispose() {
    _disposed = true;
    _resetEpisode();
  }

  void _onDisconnected() {
    if (_restarting || _disconnectTimer != null) {
      _log('disconnected, restart already pending');
      return;
    }
    _log('disconnected, ICE restart in ${fastIceRestartDelay.inSeconds} s');
    if (!_isTransportConnected()) {
      _askTransportToReconnect();
    }
    _armRestart(fastIceRestartDelay);
  }

  void _armRestart(Duration delay) {
    _disconnectTimer = _startTimer(delay, () {
      _disconnectTimer = null;
      if (_last != IceConnState.disconnected) {
        return;
      }
      if (_isAudioInterrupted()) {
        _log('still disconnected during an audio interruption, '
            'left to the resume');
        return;
      }
      restartNow('disconnected');
    });
  }

  void _onFailed() {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    if (_isAudioInterrupted()) {
      _log('failed during an audio interruption, left to the resume');
      return;
    }
    if (_restarting) {
      _log('failed, waiting for the restart in progress');
      return;
    }
    _log('failed, ICE restart now');
    restartNow('failed');
  }

  void _send(String reason) {
    if (!_sendIceRestart()) {
      _restarting = false;
      _log('ICE restart ($reason) could not be sent');
      if (_last == IceConnState.failed) {
        _endCall(IceRecoveryEnd.iceFailed);
      } else if (_last == IceConnState.disconnected) {
        _armRestart(iceRestartRetryDelay);
      }
      return;
    }
    _log('ICE restart sent ($reason)');
    _recoveryDeadline = _startTimer(iceRecoveryLimit, _onRecoveryDeadline);
  }

  void _waitForTransport(String reason) {
    Duration waited = Duration.zero;
    Duration lastAsk = Duration.zero;
    _askTransportToReconnect();
    _transportWait = _startPeriodicTimer(iceTransportPollInterval, (Timer t) {
      waited += iceTransportPollInterval;
      final bool connected = _isTransportConnected();
      if (!_isSessionOver() && !connected && waited < iceTransportWaitLimit) {
        if (waited - lastAsk >= iceTransportReconnectInterval) {
          lastAsk = waited;
          _askTransportToReconnect();
        }
        return;
      }
      t.cancel();
      if (_isSessionOver()) {
        return;
      }
      if (connected) {
        _log('SIP transport back after ${waited.inMilliseconds} ms');
        _send(reason);
        return;
      }
      _restarting = false;
      _log('SIP transport not back within '
          '${iceTransportWaitLimit.inSeconds} s, ending the call');
      _endCall(IceRecoveryEnd.transportNotBack);
    });
  }

  void _askTransportToReconnect() {
    if (_requestTransportReconnect()) {
      _log('SIP transport reconnect started');
    }
  }

  void _onRecoveryDeadline() {
    if (_isSessionOver()) {
      return;
    }
    _restarting = false;
    _log('not recovered within ${iceRecoveryLimit.inSeconds} s of the '
        'restart, ending the call');
    _endCall(IceRecoveryEnd.iceNotRecovered);
  }

  void _resetEpisode() {
    _disconnectTimer?.cancel();
    _transportWait?.cancel();
    _recoveryDeadline?.cancel();
    _disconnectTimer = null;
    _restarting = false;
  }
}

/// CMR-1139 x14: `[ICE]` lines with the time from the SIP socket connecting
/// to the first REGISTER after it (sent, then answered or failed). Only the
/// first REGISTER after each connect is logged; refreshes are not.
class RegisterAfterConnectLog {
  RegisterAfterConnectLog(
      {void Function(String message) log = iceLog, DateTime Function()? now})
      : _log = log,
        _now = now ?? DateTime.now;

  final void Function(String message) _log;
  final DateTime Function() _now;
  DateTime? _connectedAt;

  /// The SIP socket connected (again).
  void transportConnected() {
    _connectedAt = _now();
  }

  /// A REGISTER went out.
  void registerSent() {
    if (_connectedAt != null) {
      _log(
          'REGISTER sent ${_sinceConnect()} ms after the SIP socket connected');
    }
  }

  /// An answer to the REGISTER; provisional (1xx) answers are ignored.
  void registerAnswered(int status) {
    if (status >= 200) {
      _end('answered $status');
    }
  }

  /// The REGISTER ended without an answer (timeout, transport error).
  void registerFailed(String reason) => _end('failed ($reason)');

  void _end(String what) {
    if (_connectedAt == null) {
      return;
    }
    _log(
        'REGISTER $what, ${_sinceConnect()} ms after the SIP socket connected');
    _connectedAt = null;
  }

  int _sinceConnect() => _now().difference(_connectedAt!).inMilliseconds;
}
