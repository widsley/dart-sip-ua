// CMR-1131: tests for the Comdesk (legacy PBX) INVITE header helpers.
// These exercise the real functions in lib/src/comdesk_headers.dart that
// RTCSession calls (single source of truth), not a re-implementation.
// Import the pure helper directly (not the barrel) so `dart test` on the Dart
// VM does not pull in the flutter_webrtc-dependent parts of the library.

import 'package:test/test.dart';

import 'package:sip_ua/src/comdesk_headers.dart';

const List<String> _legacyLines = <String>[
  'MESH_HEADER_CALLER_CHANNEL : ch-1',
  'MESH_HEADER_VARIABLES_KEY : vk-1',
  'MESH_HEADER_EVENT_NUMBER : ev-1',
  'MESH_HEADER_SEQUENCE_ID : seq-1',
  'MESH_HEADER_CIRCUIT_NUMBER : ',
  'MESH_HEADER_CIRCUIT_TITLE : ',
  'MESH_HEADER_GROUP_NAME : ',
  'MESH_HEADER_GROUP_NUMBER : ',
  'MESH_HEADER_QUEUE_LOCAL_CHANEL : ',
  'MESH_HEADER_keys : ["MESH_HEADER_keys","MESH_HEADER_CALLER_CHANNEL",'
      '"MESH_HEADER_VARIABLES_KEY","MESH_HEADER_EVENT_NUMBER",'
      '"MESH_HEADER_SEQUENCE_ID","MESH_HEADER_CIRCUIT_NUMBER",'
      '"MESH_HEADER_CIRCUIT_TITLE","MESH_HEADER_GROUP_NAME",'
      '"MESH_HEADER_GROUP_NUMBER","MESH_HEADER_QUEUE_LOCAL_CHANEL"]',
];

void main() {
  group('comdeskHeaderLines (legacy output, unchanged)', () {
    test('the exact lines and order the legacy PBX reads', () {
      expect(
        comdeskHeaderLines(
          callerChannel: 'ch-1',
          variablesKey: 'vk-1',
          eventNumber: 'ev-1',
          sequenceId: 'seq-1',
        ),
        _legacyLines,
      );
    });

    test('a missing value is written as "null", as before', () {
      final List<String> lines = comdeskHeaderLines(sequenceId: 'seq-1');
      expect(lines.first, 'MESH_HEADER_CALLER_CHANNEL : null');
      expect(lines[1], 'MESH_HEADER_VARIABLES_KEY : null');
      expect(lines[2], 'MESH_HEADER_EVENT_NUMBER : null');
      expect(lines[3], 'MESH_HEADER_SEQUENCE_ID : seq-1');
    });
  });

  group('outgoingComdeskHeaderLines (outgoing INVITE)', () {
    test('legacy stage: the sequence id is set, so the lines are sent', () {
      expect(
        outgoingComdeskHeaderLines(<String, dynamic>{
          'CALLER_CHANNEL': 'ch-1',
          'VARIABLES_KEY': 'vk-1',
          'EVENT_NUMBER': 'ev-1',
          'SEQUENCE_ID': 'seq-1',
        }),
        _legacyLines,
      );
    });

    test('Uninote stage: no sequence id, so no MESH_HEADER_* at all', () {
      expect(outgoingComdeskHeaderLines(<String, dynamic>{}), isEmpty);
      expect(
        outgoingComdeskHeaderLines(<String, dynamic>{
          'CALLER_CHANNEL': 'ch-1',
          'SEQUENCE_ID': null,
        }),
        isEmpty,
      );
    });
  });
}
