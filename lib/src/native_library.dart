import 'dart:io';

/// Thrown when the `libcurl-impersonate` shared library cannot be located.
class ImpersonateLibraryNotFoundException implements Exception {
  ImpersonateLibraryNotFoundException(this.searched);

  /// The candidate paths that were tried, in order.
  final List<String> searched;

  @override
  String toString() =>
      'ImpersonateLibraryNotFoundException: could not find the '
      'libcurl-impersonate shared library. Set the DIO_IMPERSONATE_LIB '
      'environment variable to its path, pass `libraryPath:` to '
      'ImpersonateAdapter, or run `dart run dio_impersonate:install`.\n'
      'Searched:\n  ${searched.join('\n  ')}';
}

/// The platform-specific shared-library file names shipped by the
/// `curl-impersonate` releases, most specific first.
List<String> _platformLibraryNames() {
  if (Platform.isWindows) {
    return ['libcurl-impersonate.dll'];
  }
  if (Platform.isMacOS) {
    return ['libcurl-impersonate.4.dylib', 'libcurl-impersonate.dylib'];
  }
  return ['libcurl-impersonate.so', 'libcurl-impersonate.so.4'];
}

/// Base directories searched for a bundled library: the current working
/// directory, the directory containing the running executable, and that
/// directory's parent. The executable-relative entries matter when the host app
/// is a compiled binary launched with an unrelated working directory.
List<String> _baseDirectories() {
  final dirs = <String>[Directory.current.path];

  try {
    final exeFile = File(Platform.resolvedExecutable);
    final exeDir = exeFile.parent;
    dirs
      ..add(exeDir.path)
      ..add(exeDir.parent.path);
  } catch (_) {
    // resolvedExecutable can be unavailable in some embedded contexts.
  }

  return dirs;
}

String _join(String dir, String name) => '$dir${Platform.pathSeparator}$name';

/// Resolves the path to the `libcurl-impersonate` shared library.
///
/// Resolution order:
/// 1. [explicit], if provided and existing.
/// 2. The `DIO_IMPERSONATE_LIB` environment variable, if set and existing.
/// 3. A bundled copy under the current directory or its `.native/` folder.
///
/// If none match, the bare platform library name is returned so the OS loader
/// can resolve it via `PATH` / `LD_LIBRARY_PATH` / rpath. Throws
/// [ImpersonateLibraryNotFoundException] only when [requireExisting] is true and
/// nothing is found.
String resolveLibraryPath({String? explicit, bool requireExisting = false}) {
  final searched = <String>[];

  if (explicit != null) {
    if (File(explicit).existsSync()) return explicit;
    searched.add(explicit);
  }

  final envPath = Platform.environment['DIO_IMPERSONATE_LIB'];
  if (envPath != null && envPath.isNotEmpty) {
    if (File(envPath).existsSync()) return envPath;
    searched.add(envPath);
  }

  final names = _platformLibraryNames();
  for (final dir in _baseDirectories()) {
    // Direct hit in the base directory.
    for (final name in names) {
      final candidate = _join(dir, name);
      if (File(candidate).existsSync()) return candidate;
      searched.add(candidate);
    }

    // The install script extracts into `.native/` with a nested layout (e.g.
    // `.native/bin/` on Windows), so search it recursively as a fallback.
    final nativeDir = Directory(_join(dir, '.native'));
    if (nativeDir.existsSync()) {
      searched.add('${nativeDir.path} (recursive)');
      for (final entity
          in nativeDir.listSync(recursive: true, followLinks: false)) {
        if (entity is File && names.contains(_baseName(entity.path))) {
          return entity.path;
        }
      }
    }
  }

  if (requireExisting) {
    throw ImpersonateLibraryNotFoundException(searched);
  }

  // Fall back to the bare name and let the OS loader find it.
  return names.first;
}

String _baseName(String path) =>
    path.split(Platform.pathSeparator).last.split('/').last;
