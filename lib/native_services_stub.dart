import 'dart:async';
import 'dart:convert';

Future<void> writeSecure(String key, String value) async {}

Future<String?> readSecure(String key) async => null;

Future<void> deleteSecure(String key) async {}

Future<bool> hasPin() async => false;

Future<void> setPin(String pin) async {}

Future<bool> verifyPin(String pin) async => false;

Future<bool> biometricAvailable() async => false;

Future<bool> authenticateBiometric() async => false;

Future<Map<String, Object?>?> currentLocation() =>
    Future.error(UnsupportedError('Location is not available here.'));

Future<Map<String, Object?>?> chooseImage() async => null;

Future<Map<String, Object?>?> chooseSpreadsheet() async => null;

Future<void> saveSpreadsheet(String name, String base64) async {
  throw UnsupportedError('Spreadsheet export is unavailable on this platform.');
}

List<int> imageBytesFromBase64(String value) => base64Decode(value);

String base64FromBytes(List<int> value) => base64Encode(value);
