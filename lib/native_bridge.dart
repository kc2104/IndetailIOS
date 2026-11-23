import 'models.dart';
import 'native_services_stub.dart'
    if (dart.library.io) 'native_services_io.dart'
    if (dart.library.js_interop) 'native_services_web.dart'
    as services;

class NativeBridge {
  NativeBridge._();

  static Future<void> writeSecure(String key, String value) =>
      services.writeSecure(key, value);

  static Future<String?> readSecure(String key) => services.readSecure(key);

  static Future<void> deleteSecure(String key) => services.deleteSecure(key);

  static Future<bool> hasPin() => services.hasPin();

  static Future<void> setPin(String pin) => services.setPin(pin);

  static Future<bool> verifyPin(String pin) => services.verifyPin(pin);

  static Future<bool> biometricAvailable() => services.biometricAvailable();

  static Future<bool> authenticateBiometric() =>
      services.authenticateBiometric();

  static Future<LocationFix> currentLocation() async {
    final value = await services.currentLocation();
    if (value == null) {
      throw const DeviceException('Location could not be read.');
    }
    return LocationFix(
      latitude: (value['latitude'] as num).toDouble(),
      longitude: (value['longitude'] as num).toDouble(),
      accuracyMeters: (value['accuracy'] as num).toDouble(),
      isMocked: value['mocked'] == true,
    );
  }

  static Future<PickedImage?> chooseImage() async {
    final value = await services.chooseImage();
    if (value == null) return null;
    return PickedImage(
      name: '${value['name'] ?? 'project-photo.jpg'}',
      contentType: '${value['contentType'] ?? 'image/jpeg'}',
      bytes: services.imageBytesFromBase64('${value['base64'] ?? ''}'),
    );
  }

  static Future<PickedSpreadsheet?> chooseSpreadsheet() async {
    final value = await services.chooseSpreadsheet();
    if (value == null) return null;
    return PickedSpreadsheet(
      name: '${value['name'] ?? 'holidays.xlsx'}',
      bytes: services.imageBytesFromBase64('${value['base64'] ?? ''}'),
    );
  }

  static Future<void> saveSpreadsheet({
    required String name,
    required List<int> bytes,
  }) => services.saveSpreadsheet(name, services.base64FromBytes(bytes));
}

class PickedImage {
  const PickedImage({
    required this.name,
    required this.contentType,
    required this.bytes,
  });

  final String name;
  final String contentType;
  final List<int> bytes;
}

class PickedSpreadsheet {
  const PickedSpreadsheet({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

class DeviceException implements Exception {
  const DeviceException(this.message);

  final String message;

  @override
  String toString() => message;
}
