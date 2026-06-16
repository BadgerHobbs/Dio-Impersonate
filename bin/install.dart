// Downloads the libcurl-impersonate shared library for the current platform and
// extracts it under `.native/`, then prints the resolved library path.
//
// Usage:
//   dart run dio_impersonate:install            # default version + dest
//   dart run dio_impersonate:install <version> <destDir>
//
// Requires network access and the system `tar` (bsdtar ships with Windows 10
// 1803+, Linux and macOS).
import 'dart:ffi' show Abi;
import 'dart:io';

const String _defaultVersion = '1.5.6';
const String _repo = 'lexiforest/curl-impersonate';

/// The `libcurl-impersonate` release asset for each supported ABI.
const Map<Abi, String> _assetSuffixByAbi = {
  Abi.windowsX64: 'x86_64-win32',
  Abi.windowsArm64: 'arm64-win32',
  Abi.macosX64: 'x86_64-macos',
  Abi.macosArm64: 'arm64-macos',
  Abi.linuxX64: 'x86_64-linux-gnu',
  Abi.linuxArm64: 'aarch64-linux-gnu',
};

/// Whether [base] is a `libcurl-impersonate` shared-library file name for this
/// platform. Matches versioned variants (the Linux/macOS releases ship the real
/// library as e.g. `libcurl-impersonate.so.4.8.0`, with `.so`/`.so.4` symlinks)
/// while excluding the `.a`/`.la` static-library siblings.
bool _matchesLibrary(String base) {
  if (Platform.isWindows) return base == 'libcurl-impersonate.dll';
  if (Platform.isMacOS) {
    return base.startsWith('libcurl-impersonate') && base.endsWith('.dylib');
  }
  return base.startsWith('libcurl-impersonate.so');
}

Future<void> main(List<String> args) async {
  final version = args.isNotEmpty ? args[0] : _defaultVersion;
  final destDir = Directory(args.length > 1 ? args[1] : '.native');

  final suffix = _assetSuffixByAbi[Abi.current()];
  if (suffix == null) {
    stderr.writeln('Unsupported platform: ${Abi.current()}');
    exitCode = 1;
    return;
  }

  final asset = 'libcurl-impersonate-v$version.$suffix.tar.gz';
  final url = Uri.parse(
      'https://github.com/$_repo/releases/download/v$version/$asset');

  destDir.createSync(recursive: true);

  // Reuse an existing extracted copy if present.
  final existing = _findLibrary(destDir);
  if (existing != null) {
    stdout.writeln(existing);
    return;
  }

  stderr.writeln('Downloading $url');
  final archive = File('${destDir.path}${Platform.pathSeparator}$asset');
  await _download(url, archive);

  stderr.writeln('Extracting ${archive.path}');
  // Run from the dest dir with a relative archive name so tar does not read a
  // Windows drive-letter colon as a remote host.
  final result = Process.runSync(
    'tar',
    ['-xzf', asset],
    workingDirectory: destDir.path,
  );
  if (result.exitCode != 0) {
    stderr.writeln('tar failed: ${result.stderr}');
    exitCode = 1;
    return;
  }
  archive.deleteSync();

  final library = _findLibrary(destDir);
  if (library == null) {
    stderr.writeln('Could not find the shared library after extraction.');
    exitCode = 1;
    return;
  }

  stdout.writeln(library);
}

String? _findLibrary(Directory root) {
  if (!root.existsSync()) return null;

  final matches = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    final base = _baseName(entity.path);
    // Match by name regardless of entity type so symlinks (Link, not File) are
    // considered; existsSync() follows the link and confirms a real target.
    if (_matchesLibrary(base) && File(entity.path).existsSync()) {
      matches.add(entity.path);
    }
  }
  if (matches.isEmpty) return null;

  // Prefer the shortest base name — the unversioned `.so`/`.dylib` soname.
  matches.sort((a, b) => _baseName(a).length.compareTo(_baseName(b).length));
  return matches.first;
}

String _baseName(String path) =>
    path.split(Platform.pathSeparator).last.split('/').last;

Future<void> _download(Uri url, File destination) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('GET $url -> ${response.statusCode}');
    }
    await response.pipe(destination.openWrite());
  } finally {
    client.close();
  }
}
