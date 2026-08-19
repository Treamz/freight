import 'dart:convert';
import 'dart:io';

/// A failure to read or edit an Xcode project file.
final class PbxprojException implements Exception {
  const PbxprojException(this.message);

  final String message;

  @override
  String toString() => 'project.pbxproj: $message';
}

/// Reads a `project.pbxproj` with `plutil` and edits it as text.
///
/// The split is deliberate. A pbxproj is an OpenStep property list, and
/// `plutil` parses it correctly — but it cannot write that format back, and a
/// hand-rolled serialiser would reformat the whole file and strip the
/// `/* Runner */` annotations Xcode maintains. Inspection therefore goes
/// through the parsed tree, while edits splice well-formed text into the
/// existing sections, which keeps the diff to the lines actually added.
final class Pbxproj {
  Pbxproj._(this.path, this._text, this._parsed);

  final String path;
  String _text;
  final Map<String, Object?> _parsed;

  /// The file's current text.
  String get text => _text;

  /// Every object in the project, by id.
  Map<String, Object?> get objects =>
      (_parsed['objects'] as Map<String, Object?>?) ?? const {};

  String get rootObjectId => _parsed['rootObject']! as String;

  Map<String, Object?> get rootObject =>
      objects[rootObjectId]! as Map<String, Object?>;

  Map<String, Object?>? object(String id) =>
      objects[id] as Map<String, Object?>?;

  /// Ids of every target in the project.
  List<String> get targetIds =>
      (rootObject['targets'] as List<Object?>? ?? const []).cast<String>();

  /// The id of the target with this name, or null.
  String? targetNamed(String name) {
    for (final id in targetIds) {
      if (object(id)?['name'] == name) return id;
    }
    return null;
  }

  /// Reads the project at [path].
  static Future<Pbxproj> read(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw PbxprojException('not found at $path');
    }

    final result = await Process.run('plutil', [
      '-convert',
      'json',
      '-o',
      '-',
      path,
    ]);
    if (result.exitCode != 0) {
      throw PbxprojException('could not be parsed by plutil: ${result.stderr}');
    }

    final decoded = jsonDecode(result.stdout as String);
    if (decoded is! Map<String, Object?>) {
      throw const PbxprojException('did not parse to a dictionary');
    }

    return Pbxproj._(path, file.readAsStringSync(), decoded);
  }

  /// Builds a project from text that has already been parsed.
  ///
  /// Used by tests, which cannot depend on `plutil` being present.
  static Pbxproj fromParsed(
    String path,
    String text,
    Map<String, Object?> parsed,
  ) => Pbxproj._(path, text, parsed);

  /// Whether an id already appears anywhere in the file.
  bool containsId(String id) => _text.contains(id);

  /// A stable 24-character id derived from [seed].
  ///
  /// Deterministic so that re-running produces the same ids and therefore no
  /// diff, rather than churning the project on every invocation. Collisions
  /// are resolved by perturbing the seed, and checked against the file rather
  /// than assumed away.
  String generateId(String seed) {
    for (var attempt = 0; attempt < 1000; attempt++) {
      final candidate = _hash('$seed#$attempt');
      if (!containsId(candidate)) return candidate;
    }
    throw PbxprojException('could not find a free object id for "$seed"');
  }

  static String _hash(String seed) {
    // FNV-1a, widened to 24 hex characters by hashing three salted variants.
    // Not cryptographic and does not need to be: this only has to be stable
    // and unlikely to collide inside one file.
    final buffer = StringBuffer();
    for (final salt in const ['a', 'b', 'c']) {
      var hash = 0x811c9dc5;
      for (final unit in '$salt$seed'.codeUnits) {
        hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
      }
      buffer.write(hash.toRadixString(16).padLeft(8, '0'));
    }
    return buffer.toString().substring(0, 24).toUpperCase();
  }

  /// Inserts [body] into [section], creating the section if it is absent.
  ///
  /// [body] must be the complete, indented entry including its trailing
  /// semicolon.
  void addObject({required String section, required String body}) {
    final end = '/* End $section section */';
    final index = _text.indexOf(end);
    if (index != -1) {
      _text = _text.replaceRange(index, index, '$body\n');
      return;
    }

    // A stock Flutter project has every section this tool needs, but a
    // stripped-down one might not; sections may appear in any order inside
    // `objects`.
    final objectsStart = _text.indexOf('objects = {');
    if (objectsStart == -1) {
      throw const PbxprojException('has no objects dictionary');
    }
    final insertAt = _text.indexOf('\n', objectsStart) + 1;
    _text = _text.replaceRange(
      insertAt,
      insertAt,
      '\n/* Begin $section section */\n$body\n/* End $section section */\n',
    );
  }

  /// Appends [entry] to the list at [key] inside the object with [objectId].
  ///
  /// Pass [afterEntryContaining] to place it directly after an existing entry,
  /// which is how build phases are ordered — an embed phase appended to the end
  /// runs after Flutter's "Thin Binary" script and produces a dependency cycle.
  void addToList({
    required String objectId,
    required String key,
    required String entry,
    String? afterEntryContaining,
  }) {
    final block = _blockRange(objectId);
    final listStart = _text.indexOf('$key = (', block.start);
    if (listStart == -1 || listStart > block.end) {
      throw PbxprojException('object $objectId has no "$key" list');
    }
    final listEnd = _text.indexOf(');', listStart);
    if (listEnd == -1 || listEnd > block.end) {
      throw PbxprojException('object $objectId has a malformed "$key" list');
    }

    var insertAt = listEnd;
    if (afterEntryContaining != null) {
      final anchor = _text.indexOf(afterEntryContaining, listStart);
      if (anchor != -1 && anchor < listEnd) {
        insertAt = _text.indexOf('\n', anchor) + 1;
      }
    }

    _text = _text.replaceRange(insertAt, insertAt, '$entry\n');
  }

  /// Sets [key] in an XCBuildConfiguration's `buildSettings`, adding it if it
  /// is not there.
  ///
  /// Returns false when the setting already had a value, which is left alone:
  /// overwriting something a project deliberately configured is not this
  /// tool's business.
  bool setBuildSetting({
    required String configurationId,
    required String key,
    required String value,
  }) {
    final block = _blockRange(configurationId);
    final settingsStart = _text.indexOf('buildSettings = {', block.start);
    if (settingsStart == -1 || settingsStart > block.end) {
      throw PbxprojException(
        'configuration $configurationId has no buildSettings',
      );
    }

    final escaped = RegExp.escape(key);
    final existing = RegExp(
      '\\n\\s*$escaped\\s*=',
    ).firstMatch(_text.substring(settingsStart, block.end));
    if (existing != null) return false;

    final insertAt = _text.indexOf('\n', settingsStart) + 1;
    _text = _text.replaceRange(insertAt, insertAt, '\t\t\t\t$key = $value;\n');
    return true;
  }

  /// The text span of one object's `ID = { ... };` block.
  ({int start, int end}) _blockRange(String objectId) {
    final start = _text.indexOf('\t\t$objectId ');
    if (start == -1) {
      throw PbxprojException('object $objectId not found');
    }
    var depth = 0;
    for (var i = start; i < _text.length; i++) {
      final char = _text[i];
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return (start: start, end: i);
      }
    }
    throw PbxprojException('object $objectId is not closed');
  }

  /// Writes the edited text back.
  void save() => File(path).writeAsStringSync(_text);
}
