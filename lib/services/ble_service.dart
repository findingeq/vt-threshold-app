import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// VitalPro breathing sensor data
class VitalProData {
  final double ve; // Minute ventilation in L/min
  final double br; // Breathing rate in breaths/min
  final double tv; // Tidal volume in L (calculated: VE / BR)
  final int veRaw; // Raw byte value for VE
  final int brRaw; // Raw byte value for BR
  final DateTime timestamp;

  VitalProData({
    required this.ve,
    required this.br,
    required this.tv,
    required this.veRaw,
    required this.brRaw,
    required this.timestamp,
  });

  @override
  String toString() => 'VitalProData(ve: $ve, br: $br, tv: $tv)';
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

  // Connection state
  BluetoothDevice? _breathingSensor;
  BluetoothDevice? _hrSensor;
  bool _isScanning = false;
  bool _breathingSensorConnected = false;
  bool _hrSensorConnected = false;
  int _breathingSensorBattery = 0;
  int _hrSensorBattery = 0;
  String? _connectionError;

  // Current heart rate
  int _currentHeartRate = 0;

  // Data streams
  StreamSubscription<List<int>>? _breathingSubscription;
  StreamSubscription<List<int>>? _hrSubscription;
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
  Stream<VitalProData> get breathingDataStream => _breathingDataController.stream;
  Stream<int> get hrDataStream => _hrDataController.stream;

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

      // Listen for disconnection
      _breathingSensor!.connectionState.listen((state) {
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

      // Listen for disconnection
      _hrSensor!.connectionState.listen((state) {
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
        debugPrint('Warning: HR characteristic not found, but continuing...');
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

  /// Parse breathing data from the VitalPro sensor
  void _onBreathingData(List<int> data) {
    if (data.length < 7) return;

    // Data format (13 bytes):
    // Byte 0: Packet type (02)
    // Bytes 1-2: Timestamp/counter
    // Bytes 3-4: Reserved
    // Byte 5: VE × 10 (divide by 10 for L/min)
    // Byte 6: BR × 2 (divide by 2 for breaths/min)
    // Bytes 7-12: Reserved/other data

    final veRaw = data[5];
    final brRaw = data[6];

    final ve = veRaw / 10.0; // Convert to L/min
    final br = brRaw / 2.0; // Convert to breaths/min
    final tv = br > 0 ? ve / (br / 60.0) : 0.0; // Tidal volume = VE / (BR in breaths per second * 60)
    // Actually TV = VE / BR directly since VE is L/min and BR is breaths/min
    final tvCorrected = br > 0 ? (ve / br) : 0.0; // This gives liters per breath

    final vitalProData = VitalProData(
      ve: ve,
      br: br,
      tv: tvCorrected,
      veRaw: veRaw,
      brRaw: brRaw,
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
  }

  void _onHrSensorDisconnected() {
    _hrSensorConnected = false;
    _hrSubscription?.cancel();
    _hrSubscription = null;
    _currentHeartRate = 0;
    notifyListeners();
  }

  /// Disconnect from breathing sensor
  Future<void> disconnectBreathingSensor() async {
    await _breathingSubscription?.cancel();
    _breathingSubscription = null;
    await _breathingSensor?.disconnect();
    _breathingSensor = null;
    _breathingSensorConnected = false;
    _breathingSensorBattery = 0;
    notifyListeners();
  }

  /// Disconnect from HR sensor
  Future<void> disconnectHrSensor() async {
    await _hrSubscription?.cancel();
    _hrSubscription = null;
    await _hrSensor?.disconnect();
    _hrSensor = null;
    _hrSensorConnected = false;
    _hrSensorBattery = 0;
    _currentHeartRate = 0;
    notifyListeners();
  }

  /// Disconnect from all sensors
  Future<void> disconnectAll() async {
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
