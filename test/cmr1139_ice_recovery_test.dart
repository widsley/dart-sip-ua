// CMR-1139 x9: ICE recovery after a network drop or switch (fast policy).
// The controller is pure Dart; timers are injected so the timing is tested
// without waiting.

import 'dart:async';

import 'package:test/test.dart';

import 'package:sip_ua/src/ice_recovery.dart';

/// Manual clock for [Timer] and [Timer.periodic].
class FakeTimers {
  Duration now = Duration.zero;
  final List<_FakeTimer> _timers = <_FakeTimer>[];

  Timer timer(Duration duration, void Function() callback) =>
      _add(duration, (_) => callback(), periodic: false);

  Timer periodic(Duration period, void Function(Timer) callback) =>
      _add(period, callback, periodic: true);

  _FakeTimer _add(Duration d, void Function(Timer) cb,
      {required bool periodic}) {
    final _FakeTimer t = _FakeTimer(now + d, d, cb, periodic);
    _timers.add(t);
    return t;
  }

  void elapse(Duration d) {
    final Duration end = now + d;
    while (true) {
      final List<_FakeTimer> due = _timers
          .where((_FakeTimer t) => t.isActive && t.due <= end)
          .toList()
        ..sort((_FakeTimer a, _FakeTimer b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final _FakeTimer t = due.first;
      now = t.due;
      if (t.periodic) {
        t.due = t.due + t.period;
        t.ticks++;
      } else {
        t.active = false;
      }
      t.callback(t);
    }
    now = end;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.due, this.period, this.callback, this.periodic);
  Duration due;
  final Duration period;
  final void Function(Timer) callback;
  final bool periodic;
  bool active = true;
  int ticks = 0;

  @override
  void cancel() => active = false;

  @override
  bool get isActive => active;

  @override
  int get tick => ticks;
}

/// Records what the controller asked the session to do.
class Harness {
  Harness() {
    controller = IceRecoveryController(
      isSessionOver: () => sessionOver,
      isAudioInterrupted: () => audioInterrupted,
      isTransportConnected: () => transportConnected,
      isTransportReady: () => transportConnected && transportRegistered,
      sendIceRestart: () {
        sends.add(timers.now);
        return sendStarts;
      },
      endCall: (IceRecoveryEnd reason) => ends.add(reason),
      requestTransportReconnect: () {
        reconnects.add(timers.now);
        return reconnectStarts;
      },
      probeTransport: () => false,
      log: logs.add,
      startTimer: timers.timer,
      startPeriodicTimer: timers.periodic,
    );
  }

  final FakeTimers timers = FakeTimers();
  late final IceRecoveryController controller;
  bool sessionOver = false;
  bool audioInterrupted = false;
  bool transportConnected = true;
  bool transportRegistered = true;
  bool sendStarts = true;
  bool reconnectStarts = true;
  final List<Duration> sends = <Duration>[];
  final List<IceRecoveryEnd> ends = <IceRecoveryEnd>[];
  final List<Duration> reconnects = <Duration>[];
  final List<String> logs = <String>[];

  void elapse(int ms) => timers.elapse(Duration(milliseconds: ms));
}

void main() {
  group('iceRestartOfferConstraints', () {
    test('adds IceRestart without changing the session constraints', () {
      final Map<String, dynamic> base = <String, dynamic>{
        'mandatory': <String, dynamic>{
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
        'optional': <dynamic>[],
      };
      final Map<String, dynamic> offer = iceRestartOfferConstraints(base);
      expect(offer['mandatory']['IceRestart'], isTrue);
      expect(offer['mandatory']['OfferToReceiveAudio'], isTrue);
      expect(offer['mandatory']['OfferToReceiveVideo'], isFalse);
      expect(base['mandatory'].containsKey('IceRestart'), isFalse,
          reason: 'later hold/unhold re-INVITEs must not restart ICE');
    });

    test('works without session constraints', () {
      final Map<String, dynamic> offer = iceRestartOfferConstraints(null);
      expect(offer['mandatory'], <String, dynamic>{'IceRestart': true});
      expect(offer['optional'], <dynamic>[]);
    });

    test('renegotiate options stay audio-only (no video-upgrade path)', () {
      final Map<String, dynamic> options = iceRestartRenegotiateOptions(null);
      expect(options['rtcOfferConstraints']['mandatory']['IceRestart'], isTrue);
      expect(options['mediaConstraints'], <String, dynamic>{
        'audio': true,
        'video': false,
      });
    });
  });

  group('IceRecoveryController: disconnected', () {
    test('restarts 4 s after disconnected, not before', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(3999);
      expect(h.sends, isEmpty);
      h.elapse(1);
      expect(h.sends, <Duration>[const Duration(seconds: 4)]);
    });

    test('no restart when ICE comes back before 4 s', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(2000);
      h.controller.onIceState(IceConnState.connected);
      h.elapse(10000);
      expect(h.sends, isEmpty);
      expect(h.ends, isEmpty);
    });

    test('disconnected during an audio interruption is left to COM-130', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.audioInterrupted = true;
      h.elapse(30000);
      expect(h.sends, isEmpty);
      expect(h.ends, isEmpty);
      expect(h.controller.restarting, isFalse);
    });

    test('no restart when the session is already over', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.sessionOver = true;
      h.elapse(5000);
      expect(h.sends, isEmpty);
    });

    test('recovers, and a later drop can restart again', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(4000);
      h.controller.onIceState(IceConnState.connected);
      expect(h.controller.restarting, isFalse);
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(4000);
      expect(h.sends.length, 2);
      expect(h.ends, isEmpty);
    });

    test('x19: ends the call 20 s after ICE dropped when ICE does not recover',
        () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(19999);
      expect(h.sends, hasLength(1), reason: 'restart sent at 4 s');
      expect(h.ends, isEmpty);
      h.elapse(1);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.iceNotRecovered]);
    });
  });

  group('IceRecoveryController: SIP transport', () {
    test('waits for the SIP transport, then sends once', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(4000);
      expect(h.sends, isEmpty);
      h.elapse(2000);
      h.transportConnected = true;
      h.elapse(250);
      expect(h.sends.length, 1);
      h.elapse(1000);
      expect(h.sends.length, 1);
      expect(h.ends, isEmpty);
    });

    test(
        'x19: ends the call 20 s after the restart started without a transport',
        () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.controller.restartNow('test');
      h.elapse(19999);
      expect(h.ends, isEmpty);
      h.elapse(1);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.transportNotBack]);
      expect(h.sends, isEmpty);
    });

    test('ICE recovering while waiting for the transport stops the wait', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(5000);
      expect(h.sends, isEmpty, reason: 'still waiting for the transport');
      h.controller.onIceState(IceConnState.connected);
      final int asks = h.reconnects.length;
      h.elapse(45000);
      expect(h.ends, isEmpty, reason: 'a recovered call must not end at 20 s');
      expect(h.reconnects.length, asks, reason: 'no more reconnect requests');
      h.transportConnected = true;
      h.elapse(1000);
      expect(h.sends, isEmpty, reason: 'no ICE restart once ICE is back');
    });

    test('stops waiting quietly when the session ends', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.controller.restartNow('test');
      h.elapse(1000);
      h.sessionOver = true;
      h.transportConnected = true;
      h.elapse(20000);
      expect(h.sends, isEmpty);
      expect(h.ends, isEmpty);
    });
  });

  group('IceRecoveryController: connected but not registered (x16 review)', () {
    final int graceMs = iceRegistrationGrace.inMilliseconds;

    test('sends the restart after the registration grace instead of ending',
        () {
      final Harness h = Harness();
      h.transportRegistered = false;
      h.controller.restartNow('test');
      h.elapse(graceMs - 1);
      expect(h.sends, isEmpty, reason: 'waits for the new REGISTER first');
      expect(h.ends, isEmpty);
      h.elapse(1);
      expect(h.sends, hasLength(1),
          reason: 'an in-dialog re-INVITE does not need the registration');
      expect(h.ends, isEmpty);
      expect(h.logs.last, contains('ICE restart sent'));
      expect(
          h.logs.where((String l) => l.contains('registration')), isNotEmpty);
    });

    test('sends at once when the registration comes back in time', () {
      final Harness h = Harness();
      h.transportRegistered = false;
      h.controller.restartNow('test');
      h.elapse(2000);
      expect(h.sends, isEmpty);
      h.transportRegistered = true;
      h.elapse(250);
      expect(h.sends, hasLength(1));
      h.elapse(10000);
      expect(h.sends, hasLength(1));
    });

    test('x19: the grace counts from when the connection came back', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.transportRegistered = false;
      h.controller.restartNow('test');
      h.elapse(10000);
      h.transportConnected = true;
      h.elapse(graceMs - 1);
      expect(h.sends, isEmpty);
      h.elapse(1);
      expect(h.sends, hasLength(1));
    });

    test('does not ask the connected transport to reconnect', () {
      final Harness h = Harness();
      h.transportRegistered = false;
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(iceRecoveryDeadline.inMilliseconds);
      expect(h.reconnects, isEmpty);
    });

    test('ends the call only when the connection itself is not back', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.transportRegistered = false;
      h.controller.restartNow('test');
      h.elapse(iceRecoveryDeadline.inMilliseconds);
      expect(h.sends, isEmpty);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.transportNotBack]);
      expect(h.logs.last, contains('not connected'));
    });
  });

  group('IceRecoveryController: SIP transport reconnect (x13)', () {
    test('asks the transport to reconnect at once, then every 2 s', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.controller.restartNow('test');
      expect(h.reconnects, <Duration>[Duration.zero]);
      h.elapse(19999);
      expect(h.reconnects, <Duration>[
        for (int s = 0; s <= 18; s += 2) Duration(seconds: s),
      ]);
      h.elapse(1);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.transportNotBack]);
    });

    test('asks as soon as ICE is disconnected while the transport is down', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.controller.onIceState(IceConnState.disconnected);
      expect(h.reconnects, <Duration>[Duration.zero]);
      h.elapse(3999);
      expect(h.reconnects, <Duration>[Duration.zero]);
    });

    test('does not ask on disconnected while the transport is up', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(3999);
      expect(h.reconnects, isEmpty);
    });

    test('logs a reconnect only when an attempt started', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.reconnectStarts = false;
      h.controller.restartNow('test');
      expect(
          h.logs.where((String l) => l.contains('reconnect started')), isEmpty);
      h.reconnectStarts = true;
      h.elapse(2000);
      expect(h.logs.where((String l) => l.contains('reconnect started')),
          hasLength(1));
    });

    test('does not ask when the transport is connected', () {
      final Harness h = Harness();
      h.controller.restartNow('test');
      h.elapse(20000);
      expect(h.reconnects, isEmpty);
    });

    test('stops asking once the transport is back', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.controller.restartNow('test');
      h.elapse(3000);
      h.transportConnected = true;
      h.elapse(10000);
      expect(
          h.reconnects, <Duration>[Duration.zero, const Duration(seconds: 2)]);
      expect(h.sends.length, 1);
    });

    test('stops asking when the session ends', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.controller.restartNow('test');
      h.sessionOver = true;
      h.elapse(20000);
      expect(h.reconnects, <Duration>[Duration.zero]);
    });
  });

  group('IceRecoveryController: ends before the PBX (x19)', () {
    // The PBX ends a call about 30 s after media stops. ICE reports
    // disconnected about 5-7 s after the drop (iPhone, 19 Nov), so 20 s from
    // there ends the call about 3-5 s before the PBX.
    for (final bool transportUp in <bool>[true, false]) {
      test(
          'ends the call 20 s after ICE drops '
          '(SIP transport ${transportUp ? 'up' : 'down'})', () {
        final Harness h = Harness();
        h.transportConnected = transportUp;
        h.controller.onIceState(IceConnState.disconnected);
        h.elapse(19999);
        expect(h.ends, isEmpty);
        h.elapse(1);
        expect(h.ends, hasLength(1));
      });
    }

    test(
        'the two waits share one deadline: a transport back at 15 s still '
        'ends at 20 s (not 15 + 20 s)', () {
      final Harness h = Harness();
      h.transportConnected = false;
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(15000);
      h.transportConnected = true;
      h.elapse(250);
      expect(h.sends, hasLength(1));
      h.elapse(4749);
      expect(h.ends, isEmpty);
      h.elapse(1);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.iceNotRecovered]);
      h.elapse(60000);
      expect(h.ends, hasLength(1), reason: 'ended once');
    });

    test('the deadline during an audio interruption is left to the resume', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.audioInterrupted = true;
      h.elapse(45000);
      expect(h.ends, isEmpty);
      h.audioInterrupted = false;
      h.controller.restartNow('resume');
      expect(h.sends, hasLength(1));
      h.elapse(19999);
      expect(h.ends, isEmpty, reason: 'a new deadline from the resume');
      h.elapse(1);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.iceNotRecovered]);
    });

    test(
        'a resume late in an interruption gets a full 20 s, not the rest of '
        'the old deadline', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.audioInterrupted = true;
      h.elapse(18000);
      h.audioInterrupted = false;
      h.controller.restartNow('resume');
      expect(h.sends, hasLength(1));
      h.elapse(2000);
      expect(h.ends, isEmpty,
          reason: 'the old deadline (20 s) must not end it');
      h.elapse(17999);
      expect(h.ends, isEmpty);
      h.elapse(1);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.iceNotRecovered]);
    });

    test('an ICE failure during an interruption also leaves a full deadline',
        () {
      final Harness h = Harness();
      h.audioInterrupted = true;
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(1000);
      h.controller.onIceState(IceConnState.failed);
      h.elapse(36000);
      h.audioInterrupted = false;
      h.controller.restartNow('resume');
      h.elapse(19999);
      expect(h.ends, isEmpty);
      h.elapse(1);
      expect(h.ends, hasLength(1));
    });

    test('the registration grace starts again when the connection drops', () {
      final Harness h = Harness();
      h.transportRegistered = false;
      h.transportConnected = false;
      h.controller.restartNow('test');
      h.transportConnected = true;
      h.elapse(2000);
      h.transportConnected = false;
      h.elapse(1000);
      h.transportConnected = true;
      h.elapse(iceRegistrationGrace.inMilliseconds - 1);
      expect(h.sends, isEmpty, reason: 'the 2 s before the drop do not count');
      h.elapse(1);
      expect(h.sends, hasLength(1));
    });

    test('a restart that cannot be sent on failed ends the call only once', () {
      final Harness h = Harness();
      h.sendStarts = false;
      h.controller.onIceState(IceConnState.failed);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.iceFailed]);
      h.elapse(60000);
      expect(h.ends, hasLength(1));
    });
  });

  group('IceRecoveryController: failed', () {
    test('restarts at once on failed', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.failed);
      expect(h.sends, <Duration>[Duration.zero]);
      expect(h.ends, isEmpty);
    });

    test('failed during a restart does not send a second one', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(4000);
      h.controller.onIceState(IceConnState.failed);
      expect(h.sends.length, 1);
      expect(h.ends, isEmpty);
    });

    test('failed again before recovering ends the call', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.failed);
      h.controller.onIceState(IceConnState.checking);
      h.controller.onIceState(IceConnState.failed);
      expect(h.ends, isEmpty, reason: 'restart still in progress');
      h.elapse(20000);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.iceNotRecovered]);
      expect(h.sends.length, 1);
    });

    test('failed during an audio interruption is left to COM-130', () {
      final Harness h = Harness();
      h.audioInterrupted = true;
      h.controller.onIceState(IceConnState.failed);
      h.elapse(30000);
      expect(h.sends, isEmpty);
      expect(h.ends, isEmpty);
    });

    test('ends the call when the restart cannot be sent on failed', () {
      final Harness h = Harness();
      h.sendStarts = false;
      h.controller.onIceState(IceConnState.failed);
      expect(h.ends, <IceRecoveryEnd>[IceRecoveryEnd.iceFailed]);
    });

    test('retries 1 s later while still disconnected when the send was refused',
        () {
      final Harness h = Harness();
      h.sendStarts = false;
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(4000);
      expect(h.sends.length, 1);
      h.sendStarts = true;
      h.elapse(999);
      expect(h.sends.length, 1);
      h.elapse(1);
      expect(h.sends.length, 2);
      expect(h.controller.restarting, isTrue);
    });

    test('a restart that cannot be sent after disconnected allows a later one',
        () {
      final Harness h = Harness();
      h.sendStarts = false;
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(4000);
      expect(h.controller.restarting, isFalse);
      expect(h.ends, isEmpty);
      h.sendStarts = true;
      h.controller.onIceState(IceConnState.failed);
      expect(h.sends.length, 2);
    });
  });

  group('IceRecoveryController: restartNow and dispose', () {
    test('restartNow while a restart is in progress is ignored', () {
      final Harness h = Harness();
      h.controller.restartNow('first');
      h.controller.restartNow('second');
      expect(h.sends.length, 1);
    });

    test('dispose cancels every pending timer', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.controller.dispose();
      h.elapse(60000);
      expect(h.sends, isEmpty);
      expect(h.ends, isEmpty);
    });

    test('x19: dispose also cancels the deadline', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(4000);
      expect(h.sends, hasLength(1), reason: 'recovery deadline running');
      h.controller.dispose();
      final Harness w = Harness()..transportConnected = false;
      w.controller.restartNow('test');
      w.controller.dispose();
      h.elapse(60000);
      w.elapse(60000);
      expect(h.ends, isEmpty);
      expect(w.ends, isEmpty);
    });

    test('logs state names and decisions', () {
      final Harness h = Harness();
      h.controller.onIceState(IceConnState.disconnected);
      h.elapse(4000);
      h.controller.onIceState(IceConnState.connected);
      expect(h.logs.join('\n'), contains('disconnected'));
      expect(h.logs.join('\n'), contains('restart'));
      expect(h.logs.join('\n'), contains('recovered'));
    });
  });
}
