// Demonstrates that ImpersonateAdapter changes the TLS fingerprint Dio presents.
//
// Run with the path to the libcurl-impersonate shared library, e.g.:
//   DIO_IMPERSONATE_LIB=/path/to/libcurl-impersonate.dll dart run example/main.dart
//
// It fetches https://tls.peet.ws/api/clean twice — once with a plain Dio client
// and once through the impersonation adapter — and prints the reported JA3 hash
// and User-Agent so you can see the fingerprint switch to Chrome 131.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_impersonate/dio_impersonate.dart';

Future<void> main() async {
  const url = 'https://tls.peet.ws/api/clean';

  final plain = Dio();
  await _report('plain Dio', plain, url);

  final impersonated = Dio()
    ..httpClientAdapter = ImpersonateAdapter(
      target: ImpersonateTarget.chrome131,
      // The Windows libcurl-impersonate build ships without a CA bundle, so
      // skip verification here (mirrors curl-impersonate's --insecure).
      validateCertificates: false,
    );
  await _report('chrome131 impersonated', impersonated, url);
}

Future<void> _report(String label, Dio dio, String url) async {
  try {
    final response = await dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final json = jsonDecode(response.data!) as Map<String, dynamic>;
    print('[$label]');
    print('  ja3_hash:   ${json['ja3_hash']}');
    print('  ja4:        ${json['ja4']}');
    print('  user_agent: ${json['user_agent']}');
  } catch (error) {
    print('[$label] request failed: $error');
  }
}
