import 'dart:convert';

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.indetail.office/device');

Future<void> writeSecure(String key, String value) async {
  await _channel.invokeMethod<void>('writeSecure', {
    'key': key,
    'value': value,
  });
}

Future<String?> readSecure(String key) =>
    _channel.invokeMethod<String>('readSecure', {'key': key});

Future<void> deleteSecure(String key) async {
  await _channel.invokeMethod<void>('deleteSecure', {'key': key});
}

Future<bool> hasPin() async =>
    await _channel.invokeMethod<bool>('hasPin') ?? false;

Future<void> setPin(String pin) async {
  await _channel.invokeMethod<void>('setPin', {'pin': pin});
}

Future<bool> verifyPin(String pin) async =>
    await _channel.invokeMethod<bool>('verifyPin', {'pin': pin}) ?? false;

Future<bool> biometricAvailable() async =>
    await _channel.invokeMethod<bool>('biometricAvailable') ?? false;

Future<bool> authenticateBiometric() async =>
    await _channel.invokeMethod<bool>('authenticateBiometric') ?? false;

Future<Map<String, Object?>?> currentLocation() async {
  final value = await _channel.invokeMapMethod<String, Object?>(
    'currentLocation',
  );
  return value?.cast<String, Object?>();
}

Future<Map<String, Object?>?> chooseImage() async {
  final value = await _channel.invokeMapMethod<String, Object?>('chooseImage');
  return value?.cast<String, Object?>();
}

Future<Map<String, Object?>?> chooseSpreadsheet() async =>
    (await _channel.invokeMapMethod<String, Object?>('chooseSpreadsheet'))
        ?.cast<String, Object?>();

Future<void> saveSpreadsheet(String name, String base64) async {
  await _channel.invokeMethod<void>('saveSpreadsheet', {
    'name': name,
    'base64': base64,
  });
}

List<int> imageBytesFromBase64(String value) => base64Decode(value);

String base64FromBytes(List<int> value) => base64Encode(value);
