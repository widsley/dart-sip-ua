// CMR-1139 x9: the ICE recovery policy flows from UaSettings into the UA
// configuration that RTCSession reads. The default keeps today's behaviour.

import 'package:test/test.dart';

import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/config.dart' as config;

void main() {
  test('UaSettings defaults to the standard policy', () {
    expect(UaSettings().iceRecoveryPolicy, IceRecoveryPolicy.standard);
  });

  test('Settings defaults to the standard policy', () {
    expect(config.Settings().ice_recovery_policy, IceRecoveryPolicy.standard);
  });

  test('config load copies the policy into the UA configuration', () {
    final config.Settings src = config.Settings()
      ..ice_recovery_policy = IceRecoveryPolicy.fast;
    final config.Settings dst = config.Settings();
    expect(config.checks.optional.containsKey('ice_recovery_policy'), isTrue);
    config.checks.optional['ice_recovery_policy']!(src, dst);
    expect(dst.ice_recovery_policy, IceRecoveryPolicy.fast);
  });
}
