// CMR-1137: pure helper for the 2xx to our own re-INVITE / UPDATE.
//
// Kept side-effect free so it can be unit tested as the single source of
// truth that RTCSession actually calls.

/// Whether a 2xx to our own re-INVITE or UPDATE is a retransmission.
/// Only the first 2xx applies the answer and reports success (the `done`
/// callback of hold/unhold, `EventSucceeded`); later copies are only ACKed.
bool isRetransmitted2xx({required bool alreadySucceeded}) => alreadySucceeded;
