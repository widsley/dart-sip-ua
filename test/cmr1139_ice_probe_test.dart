// CMR-1139 x16: when a call's ICE goes `disconnected`, the controller asks the
// UA to check the SIP connection at once (fast WebSocket pings), so a dead
// connection is closed and reconnected before the ICE restart 4 s later.
// x18: lines for the answer to the ICE-restart re-INVITE.

import 'package:test/test.dart';

import 'package:sip_ua/src/ice_recovery.dart';
import 'cmr1139_ice_recovery_test.dart' show FakeTimers;

class _Probe {
  _Probe({bool withProbe = true, this.probeStarts = true}) {
    controller = IceRecoveryController(
      isSessionOver: () => false,
      isAudioInterrupted: () => false,
      isTransportConnected: () => transportReady,
      isTransportReady: () => transportReady,
      sendIceRestart: () {
        sends.add(timers.now);
        return true;
      },
      endCall: (IceRecoveryEnd reason) {},
      requestTransportReconnect: () => false,
      probeTransport: withProbe
          ? () {
              probes.add(timers.now);
              return probeStarts;
            }
          : () => false,
      log: logs.add,
      startTimer: timers.timer,
      startPeriodicTimer: timers.periodic,
    );
  }

  final FakeTimers timers = FakeTimers();
  final bool probeStarts;
  bool transportReady = true;
  final List<Duration> probes = <Duration>[];
  final List<Duration> sends = <Duration>[];
  final List<String> logs = <String>[];
  late final IceRecoveryController controller;
}

void main() {
  group('probe on disconnected', () {
    test('checks the SIP connection at once and logs it', () {
      final _Probe h = _Probe();
      h.controller.onIceState(IceConnState.connected);
      h.controller.onIceState(IceConnState.disconnected);
      expect(h.probes, <Duration>[Duration.zero]);
      expect(h.logs, contains('SIP connection check started'));
    });

    test('no second probe while the restart is pending', () {
      final _Probe h = _Probe();
      h.controller.onIceState(IceConnState.disconnected);
      h.timers.elapse(const Duration(seconds: 1));
      h.controller.onIceState(IceConnState.disconnected);
      expect(h.probes, hasLength(1));
    });

    test('a new drop after recovery probes again', () {
      final _Probe h = _Probe();
      h.controller.onIceState(IceConnState.disconnected);
      h.controller.onIceState(IceConnState.connected);
      h.controller.onIceState(IceConnState.disconnected);
      expect(h.probes, hasLength(2));
    });

    test('no log when the UA has no probe (no keepalive)', () {
      final _Probe h = _Probe(probeStarts: false);
      h.controller.onIceState(IceConnState.disconnected);
      expect(h.probes, hasLength(1));
      expect(h.logs, isNot(contains('SIP connection check started')));
    });

    test('works without a probe callback', () {
      final _Probe h = _Probe(withProbe: false);
      h.controller.onIceState(IceConnState.disconnected);
      h.timers.elapse(fastIceRestartDelay);
      expect(h.sends, <Duration>[fastIceRestartDelay]);
    });

    test(
        'the restart waits while the transport is not ready (dead socket '
        'closed by the probe, reconnecting, REGISTER pending)', () {
      final _Probe h = _Probe();
      h.controller.onIceState(IceConnState.disconnected);
      h.timers.elapse(const Duration(seconds: 2));
      h.transportReady = false;
      h.timers.elapse(const Duration(seconds: 3));
      expect(h.sends, isEmpty);
      h.transportReady = true;
      h.timers.elapse(iceTransportPollInterval);
      expect(h.sends, hasLength(1));
    });
  });

  group('restart answer lines', () {
    test('answered with the status code', () {
      expect(iceRestartAnswerLine(200), 'ICE restart answered 200');
    });

    test('failed with the status code', () {
      expect(iceRestartFailureLine(488), 'ICE restart failed 488');
      expect(iceRestartFailureLine(481), 'ICE restart failed 481');
    });

    test('failed without a response: the 2xx had no usable SDP answer', () {
      expect(iceRestartFailureLine(null),
          'ICE restart failed (2xx without a usable SDP answer)');
    });
  });
}
