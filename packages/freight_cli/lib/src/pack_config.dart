import 'package:yaml/yaml.dart';

/// When the system downloads a pack.
///
/// The three values map one to one onto both platforms: iOS download policies
/// and Android delivery modes.
enum DeliveryPolicy {
  /// Downloaded during installation; the app cannot be opened until it
  /// finishes. Android calls this install-time.
  essential,

  /// Starts during installation and may finish afterwards. Android calls this
  /// fast-follow.
  prefetch,

  /// Never downloaded automatically — the app asks. Android calls this
  /// on-demand.
  onDemand;

  static DeliveryPolicy? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// Whether this policy is driven by installation events.
  bool get isAutomatic => this != DeliveryPolicy.onDemand;
}

/// The installation events an automatic policy applies to.
enum InstallationEvent {
  firstInstallation,
  subsequentUpdate;

  static InstallationEvent? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// A malformed `freight.yaml`.
///
/// Carries the offending pack so the message can name it; a config error that
/// only says "invalid delivery" is useless in a file with nine packs.
final class FreightConfigException implements Exception {
  const FreightConfigException(this.message, {this.pack});

  final String message;
  final String? pack;

  @override
  String toString() =>
      pack == null
          ? 'freight.yaml: $message'
          : 'freight.yaml: pack "$pack": $message';
}

/// One asset pack, as declared in `freight.yaml`.
final class PackConfig {
  const PackConfig({
    required this.id,
    required this.delivery,
    required this.root,
    this.events = const {
      InstallationEvent.firstInstallation,
      InstallationEvent.subsequentUpdate,
    },
    this.files = const ['**'],
    this.exclude = const [],
    this.platforms = const ['iOS'],
  });

  /// The pack id, used as `assetPackID` and by [Freight.pack].
  final String id;

  final DeliveryPolicy delivery;

  /// Installation events an automatic policy applies to. Empty for
  /// [DeliveryPolicy.onDemand].
  final Set<InstallationEvent> events;

  /// The directory logical paths are relative to.
  ///
  /// This is what decides the paths the app reads back: a file at
  /// `<root>/nested/deep.txt` is read as `nested/deep.txt`.
  final String root;

  /// Globs, relative to [root], selecting the files in this pack.
  final List<String> files;

  /// Globs, relative to [root], removing files the [files] globs matched.
  final List<String> exclude;

  final List<String> platforms;
}

final RegExp _validPackId = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

/// A parsed `freight.yaml`.
final class FreightConfig {
  const FreightConfig(this.packs);

  final List<PackConfig> packs;

  /// Parses `freight.yaml`.
  ///
  /// Throws [FreightConfigException] with a message naming the pack at fault.
  /// Validation is deliberately strict: a typo that silently produced an empty
  /// or wrongly-delivered pack would only surface as a missing asset at
  /// runtime, on a device, after a store round trip.
  factory FreightConfig.parse(String source) {
    final YamlNode document;
    try {
      document = loadYamlNode(source);
    } on YamlException catch (e) {
      throw FreightConfigException('could not be parsed: ${e.message}');
    }

    if (document is! YamlMap) {
      throw const FreightConfigException('must be a map with a "packs" key');
    }

    final packsNode = document['packs'];
    if (packsNode == null) {
      throw const FreightConfigException('has no "packs" key');
    }
    if (packsNode is! YamlMap) {
      throw const FreightConfigException(
        '"packs" must be a map of pack id to its settings',
      );
    }
    if (packsNode.isEmpty) {
      throw const FreightConfigException('"packs" is empty');
    }

    final packs = packsNode.nodes.entries
        .map((entry) {
          final id = (entry.key as YamlScalar).value;
          if (id is! String || id.isEmpty) {
            throw const FreightConfigException('pack ids must be strings');
          }
          // Play requires this shape of an asset pack module name, and a pack
          // id is one id across both platforms — so it is enforced everywhere
          // rather than discovered at the first Android build.
          if (!_validPackId.hasMatch(id)) {
            throw FreightConfigException(
              'is not a usable pack id. It must start with a letter and '
              'contain only letters, numbers and underscores, which is what '
              'Play requires of an asset pack module',
              pack: id,
            );
          }
          return _parsePack(id, entry.value);
        })
        .toList(growable: false);

    return FreightConfig(packs);
  }

  static PackConfig _parsePack(String id, YamlNode node) {
    if (node is! YamlMap) {
      throw FreightConfigException('must be a map of settings', pack: id);
    }

    final deliveryName = node['delivery'];
    if (deliveryName == null) {
      throw FreightConfigException(
        'has no "delivery". Expected one of: '
        '${DeliveryPolicy.values.map((v) => v.name).join(', ')}',
        pack: id,
      );
    }
    final delivery =
        deliveryName is String ? DeliveryPolicy.byName(deliveryName) : null;
    if (delivery == null) {
      throw FreightConfigException(
        'has an unknown delivery "$deliveryName". Expected one of: '
        '${DeliveryPolicy.values.map((v) => v.name).join(', ')}',
        pack: id,
      );
    }

    final root = node['root'];
    if (root is! String || root.isEmpty) {
      throw FreightConfigException(
        'has no "root". It is the directory logical paths are relative to, '
        'and it decides the paths the app reads back',
        pack: id,
      );
    }

    final events = _parseEvents(id, node['events'], delivery);

    return PackConfig(
      id: id,
      delivery: delivery,
      root: root,
      events: events,
      files: _parseGlobs(id, node['files'], 'files') ?? const ['**'],
      exclude: _parseGlobs(id, node['exclude'], 'exclude') ?? const [],
      platforms:
          _parseGlobs(id, node['platforms'], 'platforms') ?? const ['iOS'],
    );
  }

  static Set<InstallationEvent> _parseEvents(
    String id,
    Object? node,
    DeliveryPolicy delivery,
  ) {
    if (node == null) {
      return delivery.isAutomatic
          ? const {
            InstallationEvent.firstInstallation,
            InstallationEvent.subsequentUpdate,
          }
          : const {};
    }

    if (!delivery.isAutomatic) {
      throw FreightConfigException(
        '"events" applies only to essential and prefetch delivery. An '
        'on-demand pack is never downloaded automatically, so there is no '
        'installation event to tie it to',
        pack: id,
      );
    }

    if (node is! YamlList || node.isEmpty) {
      throw FreightConfigException(
        '"events" must be a non-empty list',
        pack: id,
      );
    }

    return node.map((value) {
      final event = value is String ? InstallationEvent.byName(value) : null;
      if (event == null) {
        throw FreightConfigException(
          'has an unknown event "$value". Expected one of: '
          '${InstallationEvent.values.map((v) => v.name).join(', ')}',
          pack: id,
        );
      }
      return event;
    }).toSet();
  }

  static List<String>? _parseGlobs(String id, Object? node, String key) {
    if (node == null) return null;
    if (node is! YamlList || node.isEmpty) {
      throw FreightConfigException('"$key" must be a non-empty list', pack: id);
    }
    return node
        .map((value) {
          if (value is! String || value.isEmpty) {
            throw FreightConfigException(
              '"$key" must contain only non-empty strings',
              pack: id,
            );
          }
          return value;
        })
        .toList(growable: false);
  }
}
