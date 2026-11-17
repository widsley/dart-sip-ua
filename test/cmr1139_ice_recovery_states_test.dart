// CMR-1139 x9: which flutter_webrtc ICE states RTCSession hands to the
// recovery controller (fast policy). `closed` stays with the session's own
// handling, which ends the SIP session if it is still open.

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:test/test.dart';

import 'package:sip_ua/src/ice_recovery.dart';
import 'package:sip_ua/src/ice_recovery_states.dart';

void main() {
  test('maps the states the controller reacts to', () {
    expect(iceConnStateFor(RTCIceConnectionState.RTCIceConnectionStateChecking),
        IceConnState.checking);
    expect(
        iceConnStateFor(RTCIceConnectionState.RTCIceConnectionStateConnected),
        IceConnState.connected);
    expect(
        iceConnStateFor(RTCIceConnectionState.RTCIceConnectionStateCompleted),
        IceConnState.completed);
    expect(
        iceConnStateFor(
            RTCIceConnectionState.RTCIceConnectionStateDisconnected),
        IceConnState.disconnected);
    expect(iceConnStateFor(RTCIceConnectionState.RTCIceConnectionStateFailed),
        IceConnState.failed);
  });

  test('closed, new and count stay with the session', () {
    expect(iceConnStateFor(RTCIceConnectionState.RTCIceConnectionStateClosed),
        isNull);
    expect(iceConnStateFor(RTCIceConnectionState.RTCIceConnectionStateNew),
        isNull);
    expect(iceConnStateFor(RTCIceConnectionState.RTCIceConnectionStateCount),
        isNull);
  });

  test('log names drop the RTCIceConnectionState prefix', () {
    expect(
        iceStateLogName(
            RTCIceConnectionState.RTCIceConnectionStateDisconnected),
        'disconnected');
    expect(
        iceStateLogName(RTCIceConnectionState.RTCIceConnectionStateNew), 'new');
  });
}
