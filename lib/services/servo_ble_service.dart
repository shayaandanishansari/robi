import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE transport to the ESP32 pan-tilt mount (advertised as `PanTiltAgent`,
/// Nordic UART Service). Mirrors the manual `pan_tilt_ble_controller.py`:
/// scans, connects, and writes directional nudge tokens ("left"/"right"/"up"/
/// "down") to RX. The ESP holds position and slews 1° per token (STEP=1), so the
/// app stays stateless. No-ops silently while disconnected.
class ServoBleService {
  static const String deviceName = "PanTiltAgent";
  static const String _serviceUuid = "6e400001-b5b3-f393-e0a9-e50e24dcca9e";
  static const String _rxUuid      = "6e400002-b5b3-f393-e0a9-e50e24dcca9e";
  static const String _txUuid      = "6e400003-b5b3-f393-e0a9-e50e24dcca9e";

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _connecting = false;
  bool _disposed = false;

  bool get isConnected => _rxChar != null;

  /// Begin scanning for the mount and connect when found. Safe to call once at
  /// startup; retries in the background until connected (or disposed).
  Future<void> connect() async {
    if (_disposed || _connecting || isConnected) return;
    _connecting = true;

    try {
      if (await FlutterBluePlus.isSupported == false) {
        debugPrint("ServoBle: Bluetooth not supported on this device.");
        _connecting = false;
        return;
      }

      // Android 12+ requires runtime SCAN/CONNECT grants; without them
      // startScan throws and we'd silently retry forever. (iOS prompts itself
      // via Info.plist on first BLE use.)
      if (Platform.isAndroid) {
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();
        if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
            statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
          debugPrint("ServoBle: Bluetooth permissions denied.");
          _connecting = false;
          _scheduleRetry();
          return;
        }
      }

      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          // Match the advertised name (platformName is often empty until
          // connected). Results are already pre-filtered by withNames below.
          final name = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : r.device.platformName;
          if (name == deviceName) {
            await FlutterBluePlus.stopScan();
            await _scanSub?.cancel();
            _scanSub = null;
            await _connectTo(r.device);
            return;
          }
        }
      });

      debugPrint("ServoBle: Scanning for '$deviceName'...");
      await FlutterBluePlus.startScan(
        withNames: [deviceName],
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      debugPrint("ServoBle: Scan error: $e");
      _connecting = false;
      _scheduleRetry();
    }
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    try {
      _device = device;
      await device.connect(timeout: const Duration(seconds: 10));

      _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint("ServoBle: Disconnected — will retry.");
          _rxChar = null;
          _scheduleRetry();
        }
      });

      final services = await device.discoverServices();
      for (final s in services) {
        if (s.uuid.str128.toLowerCase() != _serviceUuid) continue;
        for (final c in s.characteristics) {
          final uuid = c.uuid.str128.toLowerCase();
          if (uuid == _rxUuid) {
            _rxChar = c;
          } else if (uuid == _txUuid && c.properties.notify) {
            await c.setNotifyValue(true);
            c.onValueReceived.listen((v) {
              debugPrint("ServoBle: [mount] ${String.fromCharCodes(v)}");
            });
          }
        }
      }

      if (_rxChar != null) {
        debugPrint("ServoBle: Connected to $deviceName.");
      } else {
        debugPrint("ServoBle: RX characteristic not found.");
        _scheduleRetry();
      }
    } catch (e) {
      debugPrint("ServoBle: Connect error: $e");
      _rxChar = null;
      _scheduleRetry();
    } finally {
      _connecting = false;
    }
  }

  void _scheduleRetry() {
    if (_disposed) return;
    Future.delayed(const Duration(seconds: 3), connect);
  }

  /// Send a directional nudge token ("left"/"right"/"up"/"down"). Each moves the
  /// mount 1°. Cheap no-op when disconnected.
  Future<void> sendCommand(String token) async {
    final rx = _rxChar;
    if (rx == null) return;
    try {
      await rx.write(token.codeUnits,
          withoutResponse: rx.properties.writeWithoutResponse);
    } catch (e) {
      debugPrint("ServoBle: Write error: $e");
    }
  }

  void dispose() {
    _disposed = true;
    _scanSub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    _rxChar = null;
  }
}
