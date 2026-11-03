// COM-130: tests for when our local SDP may be sent without waiting for ICE
// candidates. An ICE-restart offer sent before the new candidates exist has no
// a=candidate lines, so Asterisk answers without ice-ufrag/ice-pwd and WebRTC
// rejects that answer. Import the pure helper directly (not the barrel) so
// `dart test` on the Dart VM does not pull in flutter_webrtc.

import 'dart:io';

import 'package:test/test.dart';

import 'package:sip_ua/src/local_description_ready.dart';

void main() {
  group('isIceRestartRequested', () {
    test('legacy mandatory.IceRestart (used by the COM-130 ICE restart)', () {
      expect(
          isIceRestartRequested(<String, dynamic>{
            'mandatory': <String, dynamic>{'IceRestart': true},
            'optional': <dynamic>[],
          }),
          isTrue);
    });

    test('standard iceRestart option', () {
      expect(
          isIceRestartRequested(<String, dynamic>{'iceRestart': true}), isTrue);
    });

    test('no restart requested', () {
      expect(isIceRestartRequested(null), isFalse);
      expect(
          isIceRestartRequested(<String, dynamic>{
            'mandatory': <String, dynamic>{},
            'optional': <dynamic>[],
          }),
          isFalse);
      expect(
          isIceRestartRequested(<String, dynamic>{
            'mandatory': <String, dynamic>{'IceRestart': false},
          }),
          isFalse);
    });
  });

  group('canUseLocalDescriptionImmediately', () {
    test('gathering complete and no ICE restart: use it right away', () {
      expect(
          canUseLocalDescriptionImmediately(
              gatheringComplete: true, iceRestart: false),
          isTrue);
    });

    test('ICE restart: wait for the new candidates even if complete before',
        () {
      expect(
          canUseLocalDescriptionImmediately(
              gatheringComplete: true, iceRestart: true),
          isFalse);
    });

    test('gathering not complete: wait', () {
      expect(
          canUseLocalDescriptionImmediately(
              gatheringComplete: false, iceRestart: false),
          isFalse);
    });
  });

  // Whitespace-tolerant patterns, so a formatter change does not break them.
  group('RTCSession._createLocalDescription uses the helpers', () {
    final String source = File('lib/src/rtc_session.dart').readAsStringSync();

    test('the restart flag is read from the constraints', () {
      expect(
          RegExp(r'isIceRestartRequested\(\s*constraints\s*\)')
              .allMatches(source)
              .length,
          1);
    });

    test('the right-away path is decided by the helper', () {
      expect(
          RegExp(r'if\s*\(\s*canUseLocalDescriptionImmediately\(\s*'
                  r'gatheringComplete:\s*_iceGatheringState\s*==\s*'
                  r'RTCIceGatheringState\.RTCIceGatheringStateComplete\s*,\s*'
                  r'iceRestart:\s*iceRestart\s*,?\s*\)\s*\)')
              .allMatches(source)
              .length,
          1);
    });

    test('no other right-away check on the cached gathering state', () {
      expect(
          RegExp(r'if\s*\(\s*_iceGatheringState\s*==\s*'
                  r'RTCIceGatheringState\.RTCIceGatheringStateComplete\s*\)')
              .hasMatch(source),
          isFalse);
    });
  });
}
