/// CMR-1269: picks our binding from the Contact entries of a REGISTER 200 OK
/// (each `{'raw': String, 'parsed': NameAddrHeader}`, as the parser stores
/// them).
///
/// Only the user part identifies a binding (the registrar rewrites host, port
/// and transport). After the transport reconnects, the same UA registers again
/// from a new connection while the old binding has not expired yet, so several
/// entries can share our user part; the newest has the longest expiry left.
/// Returns null when no entry has our user part.
String? pickOwnBinding(List<dynamic> contacts, String ownUser) {
  String? best;
  num bestExpires = -1;
  for (final dynamic entry in contacts) {
    final dynamic header = entry['parsed'];
    if (header?.uri?.user != ownUser) {
      continue;
    }
    final num expires =
        num.tryParse('${header.getParam('expires') ?? ''}') ?? 0;
    if (expires > bestExpires) {
      best = entry['raw'] as String?;
      bestExpires = expires;
    }
  }
  return best;
}
