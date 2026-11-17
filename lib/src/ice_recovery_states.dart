import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'ice_recovery.dart';

/// CMR-1139 x9: the ICE states RTCSession hands to [IceRecoveryController].
/// `closed` (and `new`) stay with the session's own handling.
IceConnState? iceConnStateFor(RTCIceConnectionState state) {
  switch (state) {
    case RTCIceConnectionState.RTCIceConnectionStateChecking:
      return IceConnState.checking;
    case RTCIceConnectionState.RTCIceConnectionStateConnected:
      return IceConnState.connected;
    case RTCIceConnectionState.RTCIceConnectionStateCompleted:
      return IceConnState.completed;
    case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
      return IceConnState.disconnected;
    case RTCIceConnectionState.RTCIceConnectionStateFailed:
      return IceConnState.failed;
    default:
      return null;
  }
}

/// Short state name for the ICE log line, e.g. `disconnected`.
String iceStateLogName(RTCIceConnectionState state) {
  final String rest = state.name.substring('RTCIceConnectionState'.length);
  return rest[0].toLowerCase() + rest.substring(1);
}
