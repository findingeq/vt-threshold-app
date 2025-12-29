/// VitalPro Packet Parser
/// Parses Type 1 (Respiratory Event) packets from the VitalPro strap
///
/// Packet Format (Type 1 - 17 bytes):
/// - Byte 0: Packet ID (must be 0x01)
/// - Bytes 1-4: Tick counter (uint32 little-endian)
/// - Bytes 5-12: Ignored
/// - Bytes 13-14: VE Raw (uint16 little-endian) - Minute Ventilation L/min
/// - Bytes 15-16: Ignored (duplicate/smoothed values)

/// Parsed respiratory data from a Type 1 packet
class VitalProBreathData {
  final DateTime timestamp;      // Wall clock time
  final double elapsedSec;       // Time since anchor (from tick counter)
  final int veRaw;               // Raw VE value (L/min)
  final int adjustedTicks;       // Tick count with rollover handling

  VitalProBreathData({
    required this.timestamp,
    required this.elapsedSec,
    required this.veRaw,
    required this.adjustedTicks,
  });
}

/// Stateful parser for VitalPro BLE packets
/// Handles tick counter rollover and time anchoring
class VitalProParser {
  // Tick tracking for rollover handling
  int _accumulator = 0;
  int? _previousRawTicks;

  // Time anchoring
  DateTime? _anchorWallTime;
  int? _anchorTicks;

  // Tick rate: 25 ticks per second (empirical)
  static const double _ticksPerSecond = 25.0;

  // Rollover threshold (16-bit defensive)
  static const int _rolloverThreshold = 65536;

  /// Reset parser state (call when starting a new recording session)
  void reset() {
    _accumulator = 0;
    _previousRawTicks = null;
    _anchorWallTime = null;
    _anchorTicks = null;
  }

  /// Parse a raw BLE packet
  /// Returns null if packet is invalid or not a Type 1 packet
  VitalProBreathData? parse(List<int> rawBytes) {
    // Validation: Must be Type 1 packet with exactly 17 bytes
    if (rawBytes.isEmpty) return null;
    if (rawBytes[0] != 0x01) return null;  // Not a Type 1 packet
    if (rawBytes.length != 17) return null; // Invalid length for Type 1

    // Extract tick counter (bytes 1-4, uint32 little-endian)
    final rawTicks = _readUint32LE(rawBytes, 1);

    // Handle rollover (defensive for 16-bit firmware)
    if (_previousRawTicks != null && rawTicks < _previousRawTicks!) {
      _accumulator += _rolloverThreshold;
    }
    _previousRawTicks = rawTicks;

    // Calculate adjusted ticks
    final adjustedTicks = rawTicks + _accumulator;

    // Capture wall time now
    final now = DateTime.now();

    // Set anchor on first valid packet
    if (_anchorWallTime == null) {
      _anchorWallTime = now;
      _anchorTicks = adjustedTicks;
    }

    // Calculate elapsed time from ticks
    final elapsedSec = (adjustedTicks - _anchorTicks!) / _ticksPerSecond;

    // Calculate timestamp (anchor + elapsed)
    final timestamp = _anchorWallTime!.add(
      Duration(microseconds: (elapsedSec * 1000000).round())
    );

    // Extract VE (bytes 13-14, uint16 little-endian)
    final veRaw = _readUint16LE(rawBytes, 13);

    return VitalProBreathData(
      timestamp: timestamp,
      elapsedSec: elapsedSec,
      veRaw: veRaw,
      adjustedTicks: adjustedTicks,
    );
  }

  /// Read uint16 little-endian from bytes
  int _readUint16LE(List<int> bytes, int offset) {
    if (offset + 1 >= bytes.length) return 0;
    return bytes[offset] + (bytes[offset + 1] << 8);
  }

  /// Read uint32 little-endian from bytes
  int _readUint32LE(List<int> bytes, int offset) {
    if (offset + 3 >= bytes.length) return 0;
    return bytes[offset] +
           (bytes[offset + 1] << 8) +
           (bytes[offset + 2] << 16) +
           (bytes[offset + 3] << 24);
  }

  /// Check if anchor has been set (first valid packet received)
  bool get isAnchored => _anchorWallTime != null;

  /// Get anchor wall time (for CSV export metadata)
  DateTime? get anchorWallTime => _anchorWallTime;
}
