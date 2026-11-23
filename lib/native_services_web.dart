import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

final Map<String, String> _temporaryStorage = {};

Future<void> writeSecure(String key, String value) async {
  try {
    web.window.sessionStorage.setItem(key, value);
  } catch (_) {
    _temporaryStorage[key] = value;
  }
}

Future<String?> readSecure(String key) async {
  try {
    return web.window.sessionStorage.getItem(key) ?? _temporaryStorage[key];
  } catch (_) {
    return _temporaryStorage[key];
  }
}

Future<void> deleteSecure(String key) async {
  _temporaryStorage.remove(key);
  try {
    web.window.sessionStorage.removeItem(key);
  } catch (_) {}
}

Future<bool> hasPin() async => false;

Future<void> setPin(String pin) async {}

Future<bool> verifyPin(String pin) async => false;

Future<bool> biometricAvailable() async => false;

Future<bool> authenticateBiometric() async => false;

Future<Map<String, Object?>?> currentLocation() async {
  final completer = Completer<Map<String, Object?>>();
  web.window.navigator.geolocation.getCurrentPosition(
    ((web.GeolocationPosition position) {
      final coordinates = position.coords;
      if (!completer.isCompleted) {
        completer.complete({
          'latitude': coordinates.latitude,
          'longitude': coordinates.longitude,
          'accuracy': coordinates.accuracy,
          // Browsers do not expose an Android-style mocked-location signal.
          'mocked': false,
        });
      }
    }).toJS,
    ((web.GeolocationPositionError error) {
      if (!completer.isCompleted) {
        completer.completeError(StateError(error.message), StackTrace.current);
      }
    }).toJS,
    web.PositionOptions(
      enableHighAccuracy: true,
      timeout: 25000,
      maximumAge: 0,
    ),
  );
  return completer.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw StateError('Location request timed out.'),
  );
}

Future<Map<String, Object?>?> chooseImage() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*';
  final selected = Completer<web.File?>();
  input.addEventListener(
    'change',
    ((web.Event _) {
      if (!selected.isCompleted) selected.complete(input.files?.item(0));
    }).toJS,
  );
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!selected.isCompleted) selected.complete(null);
    }).toJS,
  );
  web.document.body?.append(input);
  input.click();
  final file = await selected.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () => null,
  );
  input.remove();
  if (file == null) return null;
  if (file.size > 8 * 1024 * 1024) {
    throw StateError('Choose an image smaller than 8 MB.');
  }
  final buffer = await file.arrayBuffer().toDart;
  final bytes = buffer.toDart.asUint8List();
  return {
    'name': file.name,
    'contentType': file.type.isEmpty ? 'image/jpeg' : file.type,
    'base64': base64Encode(bytes),
  };
}

Future<Map<String, Object?>?> chooseSpreadsheet() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept =
        '.xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  final selected = Completer<web.File?>();
  input.addEventListener(
    'change',
    ((web.Event _) {
      if (!selected.isCompleted) selected.complete(input.files?.item(0));
    }).toJS,
  );
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!selected.isCompleted) selected.complete(null);
    }).toJS,
  );
  web.document.body?.append(input);
  input.click();
  final file = await selected.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () => null,
  );
  input.remove();
  if (file == null) return null;
  if (file.size > 10 * 1024 * 1024) {
    throw StateError('Choose an Excel file smaller than 10 MB.');
  }
  final buffer = await file.arrayBuffer().toDart;
  return {
    'name': file.name,
    'base64': base64Encode(buffer.toDart.asUint8List()),
  };
}

Future<void> saveSpreadsheet(String name, String base64) async {
  final bytes = Uint8List.fromList(base64Decode(base64));
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

List<int> imageBytesFromBase64(String value) => base64Decode(value);

String base64FromBytes(List<int> value) => base64Encode(value);
