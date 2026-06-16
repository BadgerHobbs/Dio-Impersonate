/// Browser TLS/JA3 + HTTP/2 impersonation for the Dio HTTP client.
///
/// Plug [ImpersonateAdapter] into a [Dio] instance to route its requests
/// through the `libcurl-impersonate` shared library, reproducing a real
/// browser's TLS ClientHello (cipher/extension order, ALPS, certificate
/// compression, ...) and HTTP/2 settings — the transport-layer fingerprint that
/// pure-Dart HTTP clients cannot control.
library;

export 'src/impersonate_adapter.dart' show ImpersonateAdapter;
export 'src/profiles.dart' show ImpersonateTarget;
export 'src/native_library.dart' show resolveLibraryPath, ImpersonateLibraryNotFoundException;
