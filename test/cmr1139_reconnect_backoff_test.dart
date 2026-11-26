// CMR-1139 x22: the wait before the next reconnection attempt grows with the
// failed attempts up to the maximum and stays there. On the phone, after about
// 63 failed attempts (half an hour at 30 s) the wait fell back to the minimum
// and the app retried every second for as long as the network stayed blocked.

import 'package:test/test.dart';

import 'package:sip_ua/src/socket_transport.dart';

void main() {
  test('starts from the minimum and grows with the attempts', () {
    expect(recoveryDelaySeconds(1, 0.0, minSeconds: 2, maxSeconds: 30), 2);
    expect(recoveryDelaySeconds(1, 0.0, minSeconds: 1, maxSeconds: 30), 1);
    expect(recoveryDelaySeconds(1, 0.99, minSeconds: 1, maxSeconds: 30), 2);
    expect(recoveryDelaySeconds(3, 0.99, minSeconds: 1, maxSeconds: 30), 8);
    expect(recoveryDelaySeconds(5, 0.99, minSeconds: 1, maxSeconds: 30), 30);
  });

  test('stays at the maximum after many failed attempts', () {
    for (final int minSeconds in <int>[1, 2]) {
      for (final int attempts in <int>[30, 62, 63, 64, 65, 100, 2075, 5000]) {
        expect(
            recoveryDelaySeconds(attempts, 0.5,
                minSeconds: minSeconds, maxSeconds: 30),
            30,
            reason: 'attempt $attempts, minimum $minSeconds s');
      }
    }
  });
}
