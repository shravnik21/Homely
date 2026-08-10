import 'dart:io';

/// [ConnectivityGate] only catches the "device has no network
/// interface at all" case (airplane mode, wifi/data off). It's still
/// possible for a request to fail because of the network even while
/// the device reports being connected - a captive wifi portal, a bad
/// DNS, a dropped connection mid-request. This is what previously
/// surfaced as a raw `PostgrestException`/`SocketException` message
/// on the login screen (and elsewhere).
///
/// [isNetworkError] recognizes that class of failure so screens can
/// show the same friendly "check your connection" wording instead of
/// the raw exception text.
bool isNetworkError(Object error) {
  if (error is SocketException) return true;

  final message = error.toString().toLowerCase();
  const networkKeywords = [
    'socketexception',
    'failed host lookup',
    'network is unreachable',
    'connection refused',
    'connection reset',
    'connection closed',
    'connection failed',
    'clientexception',
    'software caused connection abort',
    'no address associated with hostname',
  ];
  return networkKeywords.any(message.contains);
}

/// Standard copy for a network failure - matches [NoInternetScreen]'s
/// wording so the message is consistent whether it's shown as a full
/// screen or inline (e.g. a SnackBar on a form submit).
const String noInternetMessage =
    'No internet connection. Please check your connection and try again.';

/// Turns any caught exception into copy that's safe to show a user -
/// never the raw exception text (a `PostgrestException`, a
/// `SocketException`, a stack-trace-flavoured message, etc).
///
/// - A network failure always gets [noInternetMessage], regardless of
///   what the caller passes as [fallback].
/// - Anything else gets [fallback] - a short, action-specific message
///   the caller supplies (e.g. "Could not save your changes.").
///
/// Deliberately-thrown, already-user-friendly exceptions (like
/// `BookingConflictException`, whose whole point is a clean
/// `toString()`) should keep being shown directly by the caller
/// instead of going through this function - it's only for the
/// "something failed and the exception text itself is not fit for a
/// user to read" case.
String friendlyError(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
  if (isNetworkError(error)) return noInternetMessage;
  return fallback;
}
