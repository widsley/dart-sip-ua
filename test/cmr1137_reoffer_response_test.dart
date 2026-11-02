// CMR-1137: tests for the 2xx handling of our own re-INVITE / UPDATE.
// The helper is the real function RTCSession calls. Import it directly (not
// the barrel) so `dart test` on the Dart VM does not pull in flutter_webrtc.

import 'dart:io';

import 'package:test/test.dart';

import 'package:sip_ua/src/reoffer_response.dart';

void main() {
  group('isRetransmitted2xx', () {
    test('the first 2xx is handled (answer applied, success reported)', () {
      expect(isRetransmitted2xx(alreadySucceeded: false), isFalse);
    });

    test('a 2xx after the first one is a retransmission', () {
      expect(isRetransmitted2xx(alreadySucceeded: true), isTrue);
    });
  });

  group('RTCSession uses the helper', () {
    final String source = File('lib/src/rtc_session.dart').readAsStringSync();

    test('no 2xx check compares the non-null flag with null', () {
      expect(source.contains('succeeded != null'), isFalse);
    });

    test('re-INVITE, video upgrade re-INVITE and UPDATE all call the helper',
        () {
      expect(
        'isRetransmitted2xx(alreadySucceeded: succeeded)'
            .allMatches(source)
            .length,
        3,
      );
    });
  });
}
