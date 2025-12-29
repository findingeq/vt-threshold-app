import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// VitalPro breathing sensor data
class VitalProData {
  final double ve; // Minute ventilation in L/min
  final double br; // Breathing rate in breaths/min
  final DateTime timestamp;

  VitalProData({
    required this.ve,
    required this.br,
    required this.timestamp,
  });

  @override
  String toString() => 'VitalProData(ve: $ve, br: $br)';
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

  // Connection state
  BluetoothDevice? _breathingSensor;
  BluetoothDevice? _hrSensor;
  bool _isScanning = false;
  bool _breathingSensorConnected = false;
  bool _hrSensorConnected = false;
  int _breathingSensorBattery = 0;
  int _hrSensorBattery = 0;
  String? _connectionError;

  // Data streams
  StreamSubscription<List<int>>? _breathingSubscription;
  final _breathingDataController = StreamController<VitalProData>.broadcast();

  // Getters
  bool get isScanning => _isScanning;
  bool get breathingSensorConnected => _breathingSensorConnected;
  bool get hrSensorConnected => _hrSensorConnected;
  int get breathingSensorBattery => _breathingSensorBattery;
  int get hrSensorBattery => _hrSensorBattery;
  String? get connectionError => _connectionError;
  Stream<VitalProData> get breathingDataStream => _breathingDataController.stream;

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

      // Turn on Bluetooth if it's off (Android only)
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        _connectionError = 'Please turn on Bluetooth';
        notifyListeners();
        return false;
      }

      _isScanning = true;
      notifyListeners();

      // Scan for devices starting with "TYME-"
      BluetoothDevice? foundDevice;

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withNames: ['TYME-'],
      );

      // Listen for scan results
      final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName.startsWith('TYME-')) {
            foundDevice = r.device;
            FlutterBluePlus.stopScan();
            break;
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 10));
      await scanSubscription.cancel();
      await FlutterBluePlus.stopScan();

      _isScanning = false;
      notifyListeners();

      if (foundDevice == null) {
        _connectionError = 'No VitalPro breathing sensor found. Make sure it is turned on and nearby.';
        notifyListeners();
        return false;
      }

      // Connect to the device
      _breathingSensor = foundDevice;
      await _breathingSensor!.connect(timeout: const Duration(seconds: 10));

      // Listen for disconnection
      _breathingSensor!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onBreathingSensorDisconnected();
        }
      });

      // Discover services
      final services = await _breathingSensor!.discoverServices();

      // Find and subscribe to breathing data characteristic
      bool foundBreathingChar = false;
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == _vitalProServiceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == _breathingCharUuid) {
              // Subscribe to notifications
              await char.setNotifyValue(true);
              _breathingSubscription = char.onValueReceived.listen(_onBreathingData);
              foundBreathingChar = true;
              break;
            }
          }
        }

        // Also read battery level
        if (service.uuid.toString().toLowerCase().contains(_batteryServiceUuid)) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(_batteryLevelCharUuid)) {
              final batteryValue = await char.read();
              if (batteryValue.isNotEmpty) {
                _breathingSensorBattery = batteryValue[0];
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

      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        _connectionError = 'Please turn on Bluetooth';
        notifyListeners();
        return false;
      }

      _isScanning = true;
      notifyListeners();

      // Scan for devices starting with "TymeHR"
      BluetoothDevice? foundDevice;

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withNames: ['TymeHR'],
      );

      final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName.startsWith('TymeHR')) {
            foundDevice = r.device;
            FlutterBluePlus.stopScan();
            break;
          }
        }
      });

      await Future.delayed(const Duration(seconds: 10));
      await scanSubscription.cancel();
      await FlutterBluePlus.stopScan();

      _isScanning = false;
      notifyListeners();

      if (foundDevice == null) {
        _connectionError = 'No TymeHR sensor found. Make sure it is turned on and nearby.';
        notifyListeners();
        return false;
      }

      _hrSensor = foundDevice;
      await _hrSensor!.connect(timeout: const Duration(seconds: 10));

      // Listen for disconnection
      _hrSensor!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onHrSensorDisconnected();
        }
      });

      // Discover services and read battery
      final services = await _hrSensor!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase().contains(_batteryServiceUuid)) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(_batteryLevelCharUuid)) {
              final batteryValue = await char.read();
              if (batteryValue.isNotEmpty) {
                _hrSensorBattery = batteryValue[0];
              }
            }
          }
        }
      }

      _hrSensorConnected = true;
      _connectionError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _isScanning = false;
      _connectionError = 'Connection failed: ${e.toString()}';
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

    final vitalProData = VitalProData(
      ve: ve,
      br: br,
      timestamp: DateTime.now(),
    );

    _breathingDataController.add(vitalProData);
  }

  void _onBreathingSensorDisconnected() {
    _breathingSensorConnected = false;
    _breathingSubscription?.cancel();
    _breathingSubscription = null;
    notifyListeners();
  }

  void _onHrSensorDisconnected() {
    _hrSensorConnected = false;
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
    await _hrSensor?.disconnect();
    _hrSensor = null;
    _hrSensorConnected = false;
    _hrSensorBattery = 0;
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
    disconnectAll();
    super.dispose();
  }
}
