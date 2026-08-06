import 'package:meta/meta.dart';

import '../enums/position_source.dart';
import 'position.dart';

/// A [Position] read from the background-tracking buffer, together with the
/// metadata needed to implement the drain-then-acknowledge protocol used by
/// [GeolocatorPlatform.drainBufferedPositions] and
/// [GeolocatorPlatform.acknowledgePositions].
@immutable
class BufferedPosition {
  /// Constructs a [BufferedPosition].
  const BufferedPosition({
    required this.id,
    required this.position,
    required this.recordedAt,
    required this.source,
    required this.sessionId,
  });

  /// The row id of this position in the native buffer.
  ///
  /// Pass this value back to [GeolocatorPlatform.acknowledgePositions] once
  /// the position has been safely handed off (e.g. uploaded), so it can be
  /// removed from the buffer.
  final int id;

  /// The actual location fix.
  final Position position;

  /// The moment the device wrote this position to the buffer.
  ///
  /// This is distinct from [Position.timestamp], which is when the
  /// underlying location fix was determined.
  final DateTime recordedAt;

  /// Which platform mechanism produced this position.
  final PositionSource source;

  /// Identifies the background-tracking session (start/stop cycle) this
  /// position belongs to.
  final String sessionId;

  /// Converts the supplied [Map] to an instance of [BufferedPosition].
  static BufferedPosition fromMap(dynamic message) {
    final Map<dynamic, dynamic> map = message;

    if (!map.containsKey('id')) {
      throw ArgumentError.value(
        map,
        'map',
        'The supplied map doesn\'t contain the mandatory key `id`.',
      );
    }

    if (!map.containsKey('recordedAtMillis')) {
      throw ArgumentError.value(
        map,
        'map',
        'The supplied map doesn\'t contain the mandatory key '
            '`recordedAtMillis`.',
      );
    }

    return BufferedPosition(
      id: map['id'] as int,
      position: Position.fromMap(map),
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['recordedAtMillis'] as num).toInt(),
      ),
      source: PositionSource.values[map['source'] as int],
      sessionId: map['sessionId'] as String,
    );
  }
}
