// CMR-1269: when the SIP connection last received anything. A connection
// whose network went away (Wi-Fi to cellular) gets no FIN/RST, so the app
// can only tell it is dead by the silence: the old PBX sends an empty
// keepalive every ~20 s and OPTIONS every 60 s. The sockets need
// flutter_webrtc and do not run on the Dart VM, so these tests check the
// source.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  const String mark = '_lastReceivedAt = DateTime.now();';

  // Whitespace-tolerant patterns, so a formatter change does not break them.
  String bodyOf(String source, String method) {
    final int start = source.indexOf('void $method(');
    expect(start, isNonNegative, reason: method);
    final int end = source.indexOf('\n  }\n', start);
    return source.substring(start, end);
  }

  for (final String file in <String>[
    'lib/src/transports/web_socket.dart',
    'lib/src/transports/tcp_socket.dart',
  ]) {
    group(file, () {
      final String source = File(file).readAsStringSync();

      test('an opened connection counts as activity', () {
        expect(bodyOf(source, '_onOpen'), contains(mark));
      });

      test('every message counts, before the empty keepalive is dropped', () {
        final String body = bodyOf(source, '_onMessage');
        final int at = body.indexOf(mark);
        expect(at, isNonNegative);
        expect(at, lessThan(body.indexOf('isNotEmpty')));
      });

      test('exposes lastReceivedAt', () {
        expect(
          RegExp(
            r'DateTime\?\s+get\s+lastReceivedAt\s*=>\s*'
            r'_lastReceivedAt\s*;',
          ).hasMatch(source),
          isTrue,
        );
      });
    });
  }

  test('the value reaches SIPUAHelper through the transport and the UA', () {
    expect(
      RegExp(
        r'get\s+lastReceivedAt\s*=>\s*socket\.lastReceivedAt',
      ).hasMatch(File('lib/src/socket_transport.dart').readAsStringSync()),
      isTrue,
    );
    expect(
      RegExp(
        r'get\s+lastReceivedAt\s*=>\s*'
        r'_socketTransport\?\.lastReceivedAt',
      ).hasMatch(File('lib/src/ua.dart').readAsStringSync()),
      isTrue,
    );
    expect(
      RegExp(
        r'get\s+lastReceivedAt\s*=>\s*_ua\?\.lastReceivedAt',
      ).hasMatch(File('lib/src/sip_ua_helper.dart').readAsStringSync()),
      isTrue,
    );
  });
}
