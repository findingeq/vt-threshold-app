import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// VitalPro breathing sensor data - includes all raw bytes for debugging
class VitalProData {
  final List<int> rawBytes; // All raw bytes from the notification
  final String rawHex; // Raw bytes as hex string
  final DateTime timestamp;

  VitalProData({
    required this.rawBytes,
    required this.rawHex,
    required this.timestamp,
  });

  /// Get a specific byte value (returns 0 if index out of range)
  int getByte(int index) => index < rawBytes.length ? rawBytes[index] : 0;

  @override
  String toString() => 'VitalProData(rawHex: $rawHex, bytes: ${rawBytes.length})';
}

/// BLE Service for connecting to TymeWear VitalPro sensors
class BleService extends ChangeNotifier {
  // VitalPro BLE UUIDs
  static const String _vitalProServiceUuid =
      '40b50000-30b5-11e5-a151-feff819cdc90';
  static const String _breathingCharUuid =
      '40b50004-30b5-11e5-a151-feff819cdc90';

  // Standard BLE UUIDs
  static const String _batteryServiceUuid = '180f';
  static const String _batteryLevelCharUuid = '2a19';
  static const String _heartRateServiceUuid = '180d';
  static const String _heartRateMeasurementCharUuid = '2a37';

  // Reconnection settings
  static const int _maxReconnectAttempts = 6;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  // Connection state
  BluetoothDevice? _breathingSensor;
  BluetoothDevice? _hrSensor;
  bool _isScanning = false;
  bool _breathingSensorConnected = false;
  bool _hrSensorConnected = false;
  int _breathingSensorBattery = 0;
  int _hrSensorBattery = 0;
  String? _connectionError;

  // Reconnection state
  bool _workoutActive = false;
  bool _isReconnectingBreathing = false;
  bool _isReconnectingHr = false;
  int _breathingReconnectAttempts = 0;
  int _hrReconnectAttempts = 0;

  // Current heart rate
  int _currentHeartRate = 0;

  // Data streams
  StreamSubscription<List<int>>? _breathingSubscription;
  StreamSubscription<List<int>>? _hrSubscription;
  StreamSubscription<BluetoothConnectionState>? _breathingConnectionSubscription;
  StreamSubscription<BluetoothConnectionState>? _hrConnectionSubscription;
  final _breathingDataController = StreamController<VitalProData>.broadcast();
  final _hrDataController = StreamController<int>.broadcast();

  // Getters
  bool get isScanning => _isScanning;
  bool get breathingSensorConnected => _breathingSensorConnected;
  bool get hrSensorConnected => _hrSensorConnected;
  int get breathingSensorBattery => _breathingSensorBattery;
  int get hrSensorBattery => _hrSensorBattery;
  int get currentHeartRate => _currentHeartRate;
  String? get connectionError => _connectionError;
  bool get isReconnectingBreathing => _isReconnectingBreathing;
  bool get isReconnectingHr => _isReconnectingHr;
  Stream<VitalProData> get breathingDataStream => _breathingDataController.stream;
  Stream<int> get hrDataStream => _hrDataController.stream;

  /// Set workout active state - enables auto-reconnection when true
  void setWorkoutActive(bool active) {
    _workoutActive = active;
    if (!active) {
      // Reset reconnection state when workout ends
      _isReconnectingBreathing = false;
      _isReconnectingHr = false;
      _breathingReconnectAttempts = 0;
      _hrReconnectAttempts = 0;
    }
    notifyListeners();
  }

  /// Scan for and connect to the VitalPro breathing sensor
  Future<bool> connectBreathingSensor() async {
    _connectionError = null;
    notifyListeners();

    try {
      // Check if Bluetooth is available and on
      if (await FlutterBluePlus.isSupported == false) {
        _connectionError = 'Bluetooth not supported on this device';
        notifyListeners();
        return false;
      }

      // Check Bluetooth adapter state
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _connectionError = 'Please turn on Bluetooth';
        notifyListeners();
        return false;
      }

      _isScanning = true;
      notifyListeners();

      // Scan for all devices and filter by name prefix
      BluetoothDevice? foundDevice;
      Completer<void> scanCompleter = Completer();

      // Listen for scan results
      final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final name = r.device.platformName;
          debugPrint('Found device: $name');
          if (name.startsWith('TYME-')) {
            foundDevice = r.device;
            if (!scanCompleter.isCompleted) {
              scanCompleter.complete();
            }
            break;
          }
        }
      });

      // Start scanning without name filter
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );

      // Wait for either device found or timeout
      await Future.any([
        scanCompleter.future,
        Future.delayed(const Duration(seconds: 15)),
      ]);

      await FlutterBluePlus.stopScan();
      await scanSubscription.cancel();

      _isScanning = false;
      notifyListeners();

      if (foundDevice == null) {
        _connectionError = 'No VitalPro breathing sensor found. Make sure it is turned on and nearby.';
        notifyListeners();
        return false;
      }

      debugPrint('Connecting to breathing sensor: ${foundDevice!.platformName}');

      // Connect to the device
      _breathingSensor = foundDevice;
      await _breathingSensor!.connect(timeout: const Duration(seconds: 15));

      debugPrint('Connected, discovering services...');

      // Cancel any existing connection state subscription
      await _breathingConnectionSubscription?.cancel();

      // Listen for disconnection
      _breathingConnectionSubscription = _breathingSensor!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onBreathingSensorDisconnected();
        }
      });

      // Discover services
      final services = await _breathingSensor!.discoverServices();
      debugPrint('Found ${services.length} services');

      // Find and subscribe to breathing data characteristic
      bool foundBreathingChar = false;
      for (var service in services) {
        final serviceUuid = service.uuid.toString().toLowerCase();
        debugPrint('Service: $serviceUuid');

        if (serviceUuid == _vitalProServiceUuid) {
          debugPrint('Found VitalPro service!');
          for (var char in service.characteristics) {
            final charUuid = char.uuid.toString().toLowerCase();
            debugPrint('  Characteristic: $charUuid');
            if (charUuid == _breathingCharUuid) {
              debugPrint('  Found breathing characteristic, subscribing...');
              // Subscribe to notifications
              await char.setNotifyValue(true);
              _breathingSubscription = char.onValueReceived.listen(_onBreathingData);
              foundBreathingChar = true;
              debugPrint('  Subscribed to breathing data!');
              break;
            }
          }
        }

        // Also read battery level
        if (serviceUuid.contains(_batteryServiceUuid)) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(_batteryLevelCharUuid)) {
              try {
                final batteryValue = await char.read();
                if (batteryValue.isNotEmpty) {
                  _breathingSensorBattery = batteryValue[0];
                  debugPrint('Battery level: $_breathingSensorBattery%');
                }
              } catch (e) {
                debugPrint('Could not read battery: $e');
              }
            }
          }
        }
      }

      if (!foundBreathingChar) {
        _connectionError = 'Connected but breathing characteristic not found';
        await _breathingSensor!.disconnect();
        notifyListeners();
        return false;
      }

      _breathingSensorConnected = true;
      _connectionError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _isScanning = false;
      _connectionError = 'Connection failed: ${e.toString()}';
      debugPrint('Connection error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Scan for and connect to the heart rate sensor
  Future<bool> connectHrSensor() async {
    _connectionError = null;
    notifyListeners();

    try {
      if (await FlutterBluePlus.isSupported == false) {
        _connectionError = 'Bluetooth not supported on this device';
        notifyListeners();
        return false;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _connectionError = 'Please turn on Bluetooth';
        notifyListeners();
        return false;
      }

      _isScanning = true;
      notifyListeners();

      // Scan for all devices and filter by name prefix
      BluetoothDevice? foundDevice;
      Completer<void> scanCompleter = Completer();

      final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final name = r.device.platformName;
          debugPrint('Found device: $name');
          if (name.startsWith('TymeHR')) {
            foundDevice = r.device;
            if (!scanCompleter.isCompleted) {
              scanCompleter.complete();
            }
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );

      await Future.any([
        scanCompleter.future,
        Future.delayed(const Duration(seconds: 15)),
      ]);

      await FlutterBluePlus.stopScan();
      await scanSubscription.cancel();

      _isScanning = false;
      notifyListeners();

      if (foundDevice == null) {
        _connectionError = 'No TymeHR sensor found. Make sure it is turned on and nearby.';
        notifyListeners();
        return false;
      }

      debugPrint('Connecting to HR sensor: ${foundDevice!.platformName}');

      _hrSensor = foundDevice;
      await _hrSensor!.connect(timeout: const Duration(seconds: 15));

      debugPrint('Connected, discovering services...');

      // Cancel any existing connection state subscription
      await _hrConnectionSubscription?.cancel();

      // Listen for disconnection
      _hrConnectionSubscription = _hrSensor!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onHrSensorDisconnected();
        }
      });

      // Discover services
      final services = await _hrSensor!.discoverServices();
      debugPrint('Found ${services.length} services');

      bool foundHrChar = false;
      for (var service in services) {
        final serviceUuid = service.uuid.toString().toLowerCase();
        debugPrint('Service: $serviceUuid');

        // Heart Rate Service
        if (serviceUuid.contains(_heartRateServiceUuid)) {
          debugPrint('Found Heart Rate service!');
          for (var char in service.characteristics) {
            final charUuid = char.uuid.toString().toLowerCase();
            if (charUuid.contains(_heartRateMeasurementCharUuid)) {
              debugPrint('  Found HR measurement characteristic, subscribing...');
              await char.setNotifyValue(true);
              _hrSubscription = char.onValueReceived.listen(_onHrData);
              foundHrChar = true;
              debugPrint('  Subscribed to HR data!');
              break;
            }
          }
        }

        // Battery Service
        if (serviceUuid.contains(_batteryServiceUuid)) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(_batteryLevelCharUuid)) {
              try {
                final batteryValue = await char.read();
                if (batteryValue.isNotEmpty) {
                  _hrSensorBattery = batteryValue[0];
                  debugPrint('HR Battery level: $_hrSensorBattery%');
                }
              } catch (e) {
                debugPrint('Could not read HR battery: $e');
              }
            }
          }
        }
      }

      if (!foundHrChar) {
        _connectionError = 'Connected but HR characteristic not found';
        await _hrSensor!.disconnect();
        notifyListeners();
        return false;
      }

      _hrSensorConnected = true;
      _connectionError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _isScanning = false;
      _connectionError = 'Connection failed: ${e.toString()}';
      debugPrint('HR Connection error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Capture raw breathing data from the VitalPro sensor
  void _onBreathingData(List<int> data) {
    if (data.isEmpty) return;

    // Convert bytes to hex string for debugging
    final hexString = data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

    final vitalProData = VitalProData(
      rawBytes: List.from(data),
      rawHex: hexString,
      timestamp: DateTime.now(),
    );

    _breathingDataController.add(vitalProData);
  }

  /// Parse heart rate data from standard BLE HR service
  void _onHrData(List<int> data) {
    if (data.isEmpty) return;

    // Standard BLE Heart Rate Measurement format:
    // Byte 0: Flags
    //   - Bit 0: Heart Rate Value Format (0 = UINT8, 1 = UINT16)
    // Byte 1 (and 2 if 16-bit): Heart Rate Value

    final flags = data[0];
    final is16Bit = (flags & 0x01) == 1;

    int hr;
    if (is16Bit && data.length >= 3) {
      hr = data[1] + (data[2] << 8);
    } else if (data.length >= 2) {
      hr = data[1];
    } else {
      return;
    }

    _currentHeartRate = hr;
    _hrDataController.add(hr);
    notifyListeners();
  }

  void _onBreathingSensorDisconnected() {
    _breathingSensorConnected = false;
    _breathingSubscription?.cancel();
    _breathingSubscription = null;
    notifyListeners();

    // Attempt auto-reconnection if workout is active
    if (_workoutActive && _breathingSensor != null) {
      debugPrint('Breathing sensor disconnected during workout - attempting reconnection');
      _attemptBreathingSensorReconnect();
    }
  }

  void _onHrSensorDisconnected() {
    _hrSensorConnected = false;
    _hrSubscription?.cancel();
    _hrSubscription = null;
    _currentHeartRate = 0;
    notifyListeners();

    // Attempt auto-reconnection if workout is active
    if (_workoutActive && _hrSensor != null) {
      debugPrint('HR sensor disconnected during workout - attempting reconnection');
      _attemptHrSensorReconnect();
    }
  }

  /// Attempt to reconnect to the breathing sensor
  Future<void> _attemptBreathingSensorReconnect() async {
    if (_isReconnectingBreathing || !_workoutActive) return;

    _isReconnectingBreathing = true;
    _breathingReconnectAttempts = 0;
    notifyListeners();

    while (_workoutActive &&
        !_breathingSensorConnected &&
        _breathingReconnectAttempts < _maxReconnectAttempts) {
      _breathingReconnectAttempts++;
      debugPrint('Breathing sensor reconnect attempt $_breathingReconnectAttempts/$_maxReconnectAttempts');

      try {
        // Try to reconnect to the known device
        if (_breathingSensor != null) {
          await _breathingSensor!.connect(timeout: const Duration(seconds: 10));

          // Re-discover services and subscribe
          final services = await _breathingSensor!.discoverServices();
          for (var service in services) {
            final serviceUuid = service.uuid.toString().toLowerCase();
            if (serviceUuid == _vitalProServiceUuid) {
              for (var char in service.characteristics) {
                final charUuid = char.uuid.toString().toLowerCase();
                if (charUuid == _breathingCharUuid) {
                  await char.setNotifyValue(true);
                  _breathingSubscription = char.onValueReceived.listen(_onBreathingData);
                  _breathingSensorConnected = true;
                  _isReconnectingBreathing = false;
                  _breathingReconnectAttempts = 0;
                  debugPrint('Breathing sensor reconnected successfully!');
                  notifyListeners();
                  return;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Breathing sensor reconnect attempt failed: $e');
      }

      // Wait before next attempt
      if (_workoutActive && !_breathingSensorConnected) {
        await Future.delayed(_reconnectDelay);
      }
    }

    _isReconnectingBreathing = false;
    if (!_breathingSensorConnected) {
      debugPrint('Breathing sensor reconnection failed after $_maxReconnectAttempts attempts');
    }
    notifyListeners();
  }

  /// Attempt to reconnect to the HR sensor
  Future<void> _attemptHrSensorReconnect() async {
    if (_isReconnectingHr || !_workoutActive) return;

    _isReconnectingHr = true;
    _hrReconnectAttempts = 0;
    notifyListeners();

    while (_workoutActive &&
        !_hrSensorConnected &&
        _hrReconnectAttempts < _maxReconnectAttempts) {
      _hrReconnectAttempts++;
      debugPrint('HR sensor reconnect attempt $_hrReconnectAttempts/$_maxReconnectAttempts');

      try {
        // Try to reconnect to the known device
        if (_hrSensor != null) {
          await _hrSensor!.connect(timeout: const Duration(seconds: 10));

          // Re-discover services and subscribe
          final services = await _hrSensor!.discoverServices();
          for (var service in services) {
            final serviceUuid = service.uuid.toString().toLowerCase();
            if (serviceUuid.contains(_heartRateServiceUuid)) {
              for (var char in service.characteristics) {
                final charUuid = char.uuid.toString().toLowerCase();
                if (charUuid.contains(_heartRateMeasurementCharUuid)) {
                  await char.setNotifyValue(true);
                  _hrSubscription = char.onValueReceived.listen(_onHrData);
                  _hrSensorConnected = true;
                  _isReconnectingHr = false;
                  _hrReconnectAttempts = 0;
                  debugPrint('HR sensor reconnected successfully!');
                  notifyListeners();
                  return;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('HR sensor reconnect attempt failed: $e');
      }

      // Wait before next attempt
      if (_workoutActive && !_hrSensorConnected) {
        await Future.delayed(_reconnectDelay);
      }
    }

    _isReconnectingHr = false;
    if (!_hrSensorConnected) {
      debugPrint('HR sensor reconnection failed after $_maxReconnectAttempts attempts');
    }
    notifyListeners();
  }

  /// Disconnect from breathing sensor
  Future<void> disconnectBreathingSensor() async {
    _isReconnectingBreathing = false;
    _breathingReconnectAttempts = 0;
    await _breathingSubscription?.cancel();
    _breathingSubscription = null;
    await _breathingConnectionSubscription?.cancel();
    _breathingConnectionSubscription = null;
    await _breathingSensor?.disconnect();
    _breathingSensor = null;
    _breathingSensorConnected = false;
    _breathingSensorBattery = 0;
    notifyListeners();
  }

  /// Disconnect from HR sensor
  Future<void> disconnectHrSensor() async {
    _isReconnectingHr = false;
    _hrReconnectAttempts = 0;
    await _hrSubscription?.cancel();
    _hrSubscription = null;
    await _hrConnectionSubscription?.cancel();
    _hrConnectionSubscription = null;
    await _hrSensor?.disconnect();
    _hrSensor = null;
    _hrSensorConnected = false;
    _hrSensorBattery = 0;
    _currentHeartRate = 0;
    notifyListeners();
  }

  /// Disconnect from all sensors
  Future<void> disconnectAll() async {
    _workoutActive = false;
    await disconnectBreathingSensor();
    await disconnectHrSensor();
  }

  @override
  void dispose() {
    _breathingDataController.close();
    _hrDataController.close();
    disconnectAll();
    super.dispose();
  }
}
