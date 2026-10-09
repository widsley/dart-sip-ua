// COM-130: tests for the audio-interruption decision helpers.
// These exercise the real functions in lib/src/com130.dart that RTCSession
// calls (single source of truth), not a re-implementation.
// Import the pure helper directly (not the barrel) so `dart test` on the Dart
// VM does not pull in the flutter_webrtc-dependent parts of the library.

import 'package:test/test.dart';

import 'package:sip_ua/src/com130.dart';

void main() {
  group('resumeAfterInterruptionDecision', () {
    test('held + ICE failed/disconnected -> unhold + ICE restart', () {
      final r = resumeAfterInterruptionDecision(
        terminated: false,
        localHold: true,
        iceFailedOrDisconnected: true,
        isAttemptingIceRestart: false,
      );
      expect(r.unhold, isTrue);
      expect(r.iceRestart, isTrue);
    });

    test('not held but ICE failed -> restart only', () {
      final r = resumeAfterInterruptionDecision(
        terminated: false,
        localHold: false,
        iceFailedOrDisconnected: true,
        isAttemptingIceRestart: false,
      );
      expect(r.unhold, isFalse);
      expect(r.iceRestart, isTrue);
    });

    test('not held + ICE healthy -> no-op', () {
      final r = resumeAfterInterruptionDecision(
        terminated: false,
        localHold: false,
        iceFailedOrDisconnected: false,
        isAttemptingIceRestart: false,
      );
      expect(r.unhold, isFalse);
      expect(r.iceRestart, isFalse);
    });

    test('already attempting restart -> unhold but no duplicate restart', () {
      final r = resumeAfterInterruptionDecision(
        terminated: false,
        localHold: true,
        iceFailedOrDisconnected: true,
        isAttemptingIceRestart: true,
      );
      expect(r.unhold, isTrue);
      expect(r.iceRestart, isFalse);
    });

    test('terminated session -> no-op', () {
      final r = resumeAfterInterruptionDecision(
        terminated: true,
        localHold: true,
        iceFailedOrDisconnected: true,
        isAttemptingIceRestart: false,
      );
      expect(r.unhold, isFalse);
      expect(r.iceRestart, isFalse);
    });
  });

  group('shouldTeardownOnIceFailed', () {
    test('during interruption -> suppress teardown', () {
      expect(shouldTeardownOnIceFailed(audioInterrupted: true), isFalse);
    });

    test('normal -> teardown', () {
      expect(shouldTeardownOnIceFailed(audioInterrupted: false), isTrue);
    });
  });
}
