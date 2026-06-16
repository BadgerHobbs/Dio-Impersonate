# Dio-Impersonate

Browser **TLS/JA3 + HTTP/2 impersonation** for the Dart [Dio](https://pub.dev/packages/dio)
HTTP client — the Dio equivalent of
[curl-impersonate](https://github.com/lexiforest/curl-impersonate).

Many anti-bot systems (e.g. Cloudflare managed challenges) fingerprint the **TLS ClientHello**
(cipher/extension order, ALPS, certificate compression — the JA3/JA4 hash) and **HTTP/2 settings**,
not just request headers. Dart's `dart:io` socket layer exposes none of that, so a plain Dio client
is easily fingerprinted and blocked. `dio_impersonate` routes Dio requests through the
`libcurl-impersonate` shared library via `dart:ffi`, reproducing a real browser's transport-layer
fingerprint.

> You cannot beat a TLS fingerprint with headers. This package changes the actual handshake.

## How it works

`ImpersonateAdapter` implements Dio's `HttpClientAdapter`. Each request is performed on a short-lived
background isolate by `libcurl-impersonate`, whose `curl_easy_impersonate(handle, "chrome131", 1)`
call sets the cipher list, TLS extension order/permutation, ALPS, certificate compression, HTTP/2
pseudo-header order, and the browser's base headers in one shot. Your own headers (cookies,
content-type, ...) are layered on top; the browser-fingerprint headers are left to the library.

## Requirements

- Dart SDK ≥ 3.7
- The `libcurl-impersonate` shared library for your platform (downloaded by the install script
  below), and the system `tar` to extract it.

## Install the native library

```sh
dart run dio_impersonate:install
```

This downloads the matching `libcurl-impersonate` release into `.native/` and prints the resolved
library path. The adapter finds it automatically; you can also point at a specific file with the
`DIO_IMPERSONATE_LIB` environment variable or the `libraryPath:` constructor argument.

## Usage

```dart
import 'package:dio/dio.dart';
import 'package:dio_impersonate/dio_impersonate.dart';

final dio = Dio()
  ..httpClientAdapter = ImpersonateAdapter(
    target: ImpersonateTarget.chrome131,
    // libraryPath: '/path/to/libcurl-impersonate.dll', // optional
    // validateCertificates: false,                     // curl's --insecure
  );

final response = await dio.get('https://example.com');
```

See [`example/main.dart`](example/main.dart) for a runnable demo that prints the JA3/JA4 hash with and
without impersonation.

## Targets

`ImpersonateTarget.chrome131` is provided as a constant. Any identifier supported by the linked
`libcurl-impersonate` build (the same names accepted by curl-impersonate's `--impersonate` flag,
e.g. `chrome131`, `ff117`, `safari180`) works via `ImpersonateTarget.fromName('...')`.

## Limitations

- TLS certificate verification needs a CA bundle. Some prebuilt libraries (notably the Windows
  build) ship without one; set `validateCertificates: false` to mirror curl's `--insecure`.
- The adapter follows redirects inside libcurl (honouring `RequestOptions.followRedirects` /
  `maxRedirects`) and returns the final response.
