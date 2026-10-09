// CMR-1131: pure helpers for the Comdesk (legacy PBX) INVITE headers
// (`MESH_HEADER_*`).
//
// These are kept side-effect free so they can be unit tested as the single
// source of truth that RTCSession actually calls (rather than tests
// re-implementing the header lines).

import 'dart:convert';

const String EXTRA_HEADERS_HEAD = 'MESH_HEADER_';

/// The `MESH_HEADER_*` lines the legacy Comdesk PBX reads, in the order sent.
/// A missing value is written as `null`, as it always has been.
List<String> comdeskHeaderLines({
  Object? callerChannel,
  Object? variablesKey,
  Object? eventNumber,
  Object? sequenceId,
}) {
  final Map<String, Object?> values = <String, Object?>{
    'CALLER_CHANNEL': callerChannel,
    'VARIABLES_KEY': variablesKey,
    'EVENT_NUMBER': eventNumber,
    'SEQUENCE_ID': sequenceId,
    'CIRCUIT_NUMBER': '',
    'CIRCUIT_TITLE': '',
    'GROUP_NAME': '',
    'GROUP_NUMBER': '',
    'QUEUE_LOCAL_CHANEL': '',
  };
  final String headerKeysKey = '${EXTRA_HEADERS_HEAD}keys';
  final List<String> keysArr = <String>[headerKeysKey];
  final List<String> lines = <String>[];
  values.forEach((String key, Object? value) {
    final String headerKey = '$EXTRA_HEADERS_HEAD$key';
    keysArr.add(headerKey);
    lines.add('$headerKey : $value');
  });
  lines.add('$headerKeysKey : ${jsonEncode(keysArr)}');
  return lines;
}

/// Comdesk lines for an outgoing INVITE: only when the caller set a sequence
/// id (legacy stage). The Uninote stage sends none (Phase 2 design §2.2).
List<String> outgoingComdeskHeaderLines(Map<String, dynamic> options) =>
    options['SEQUENCE_ID'] == null
        ? const <String>[]
        : comdeskHeaderLines(
            callerChannel: options['CALLER_CHANNEL'],
            variablesKey: options['VARIABLES_KEY'],
            eventNumber: options['EVENT_NUMBER'],
            sequenceId: options['SEQUENCE_ID'],
          );
