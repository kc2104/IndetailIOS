package com.indetail.office

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.hardware.biometrics.BiometricPrompt
import android.hardware.fingerprint.FingerprintManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec

class MainActivity : FlutterActivity() {
    private val channelName = "com.indetail.office/device"
    private val prefs by lazy { getSharedPreferences("indetail_device", Activity.MODE_PRIVATE) }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var locationResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null
    private var activeLocationListener: LocationListener? = null
    private var bestLocation: Location? = null
    private var photoResult: MethodChannel.Result? = null
    private var spreadsheetResult: MethodChannel.Result? = null
    private var spreadsheetSaveResult: MethodChannel.Result? = null
    private var pendingSpreadsheetBase64: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handleMethod(call, result) }
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "writeSecure" -> {
                val key = call.argument<String>("key")
                val value = call.argument<String>("value")
                if (key == null || value == null) result.error("invalid_arguments", "Missing secure value", null)
                else try {
                    saveSecure(key, value)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("secure_storage", error.message, null)
                }
            }
            "readSecure" -> {
                val key = call.argument<String>("key")
                result.success(if (key == null) null else readSecure(key))
            }
            "deleteSecure" -> {
                val key = call.argument<String>("key")
                if (key != null) prefs.edit().remove(key).commit()
                result.success(null)
            }
            "hasPin" -> result.success(readSecure("pin_record") != null)
            "setPin" -> setPin(call, result)
            "verifyPin" -> verifyPin(call, result)
            "biometricAvailable" -> result.success(hasBiometric())
            "authenticateBiometric" -> authenticateBiometric(result)
            "currentLocation" -> requestLocation(result)
            "chooseImage" -> chooseImage(result)
            "chooseSpreadsheet" -> chooseSpreadsheet(result)
            "saveSpreadsheet" -> saveSpreadsheet(call, result)
            else -> result.notImplemented()
        }
    }

    private fun setPin(call: MethodCall, result: MethodChannel.Result) {
        val pin = call.argument<String>("pin")
        if (pin == null || !pin.matches(Regex("^[0-9]{6}$"))) {
            result.error("invalid_pin", "PIN must contain exactly six digits", null)
            return
        }
        try {
            val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
            val hash = derivePinHash(pin, salt)
            saveSecure("pin_record", Base64.encodeToString(salt + hash, Base64.NO_WRAP))
            saveSecure("pin_failures", "0")
            saveSecure("pin_lockout_until", "0")
            result.success(null)
        } catch (error: Exception) {
            result.error("pin_setup", error.message, null)
        }
    }

    private fun verifyPin(call: MethodCall, result: MethodChannel.Result) {
        val pin = call.argument<String>("pin")
        if (pin == null || !pin.matches(Regex("^[0-9]{6}$"))) {
            result.success(false)
            return
        }
        try {
            val lockoutUntil = readSecure("pin_lockout_until")?.toLongOrNull() ?: 0L
            if (System.currentTimeMillis() < lockoutUntil) {
                result.error("pin_locked", "Too many attempts. Try again in a short while.", null)
                return
            }
            val record = readSecure("pin_record")
            if (record == null) {
                result.error("pin_missing", "Set up a PIN after signing in.", null)
                return
            }
            val decoded = Base64.decode(record, Base64.NO_WRAP)
            val salt = decoded.copyOfRange(0, 16)
            val expected = decoded.copyOfRange(16, decoded.size)
            val actual = derivePinHash(pin, salt)
            if (MessageDigest.isEqual(expected, actual)) {
                saveSecure("pin_failures", "0")
                saveSecure("pin_lockout_until", "0")
                result.success(true)
            } else {
                val failures = (readSecure("pin_failures")?.toIntOrNull() ?: 0) + 1
                if (failures >= 5) {
                    saveSecure("pin_failures", "0")
                    saveSecure("pin_lockout_until", (System.currentTimeMillis() + 30_000L).toString())
                } else {
                    saveSecure("pin_failures", failures.toString())
                }
                result.success(false)
            }
        } catch (error: Exception) {
            result.error("pin_verify", error.message, null)
        }
    }

    private fun derivePinHash(pin: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(pin.toCharArray(), salt, 210_000, 256)
        return try {
            SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        } finally {
            spec.clearPassword()
        }
    }

    @Suppress("DEPRECATION")
    private fun hasBiometric(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bm = getSystemService(android.hardware.biometrics.BiometricManager::class.java)
            if (bm != null) {
                val authenticators = android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG or
                        android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_WEAK
                val status = bm.canAuthenticate(authenticators)
                if (status == android.hardware.biometrics.BiometricManager.BIOMETRIC_SUCCESS) {
                    return true
                }
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val bm = getSystemService(android.hardware.biometrics.BiometricManager::class.java)
            if (bm != null) {
                val status = bm.canAuthenticate()
                if (status == android.hardware.biometrics.BiometricManager.BIOMETRIC_SUCCESS) {
                    return true
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val manager = getSystemService(FingerprintManager::class.java)
            if (manager != null && manager.isHardwareDetected && manager.hasEnrolledFingerprints()) {
                return true
            }
        }
        return false
    }

    private fun authenticateBiometric(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || !hasBiometric()) {
            result.success(false)
            return
        }
        try {
            val builder = BiometricPrompt.Builder(this)
                .setTitle("Unlock INDETAIL")
                .setSubtitle("Confirm your fingerprint or face")
                .setNegativeButton("Use PIN", mainExecutor) { _, _ -> result.success(false) }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setAllowedAuthenticators(
                    android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_WEAK
                )
            }

            val prompt = builder.build()
            prompt.authenticate(
                CancellationSignal(),
                mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult?) {
                        result.success(true)
                    }
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                        result.success(false)
                    }
                    override fun onAuthenticationFailed() {
                        // Leave the platform prompt open so the user can retry.
                    }
                },
            )
        } catch (error: Exception) {
            result.error("biometric", error.message, null)
        }
    }

    private fun requestLocation(result: MethodChannel.Result) {
        if (locationResult != null || permissionResult != null) {
            result.error("location_busy", "A location check is already running.", null)
            return
        }
        val fineGranted = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fineGranted) {
            permissionResult = result
            requestPermissions(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                LOCATION_PERMISSION_REQUEST,
            )
            return
        }
        locationResult = result
        beginLocationUpdates()
    }

    @Suppress("DEPRECATION")
    private fun beginLocationUpdates() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            finishLocation(null, "Precise location access is required to verify an attendance site.")
            return
        }
        val manager = getSystemService(LOCATION_SERVICE) as LocationManager
        val providers = try {
            manager.getProviders(true).filter {
                it == LocationManager.GPS_PROVIDER || it == LocationManager.NETWORK_PROVIDER
            }
        } catch (_: Exception) {
            emptyList()
        }
        if (providers.isEmpty()) {
            finishLocation(null, "Turn on location services and try again.")
            return
        }
        bestLocation = null
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                val previous = bestLocation
                if (previous == null || location.accuracy < previous.accuracy) bestLocation = location
                if (location.accuracy <= 20f) finishLocation(bestLocation, null)
            }
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
            @Deprecated("Deprecated by Android")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        activeLocationListener = listener
        try {
            providers.forEach { provider ->
                manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
            }
        } catch (error: SecurityException) {
            finishLocation(null, "Location permission is required for attendance.")
            return
        } catch (error: Exception) {
            finishLocation(null, error.message ?: "Could not start a location check.")
            return
        }
        mainHandler.postAtTime({
            val location = bestLocation
            if (location == null) finishLocation(null, "No GPS fix arrived. Move to an open area and retry.")
            else finishLocation(location, null)
        }, LOCATION_TIMEOUT_TOKEN, android.os.SystemClock.uptimeMillis() + LOCATION_TIMEOUT_MS)
    }

    @Suppress("DEPRECATION")
    private fun finishLocation(location: Location?, error: String?) {
        val result = locationResult ?: return
        locationResult = null
        activeLocationListener?.let { listener ->
            try { (getSystemService(LOCATION_SERVICE) as LocationManager).removeUpdates(listener) } catch (_: Exception) {}
        }
        activeLocationListener = null
        mainHandler.removeCallbacksAndMessages(LOCATION_TIMEOUT_TOKEN)
        when {
            error != null -> result.error("location", error, null)
            location != null -> result.success(mapOf(
                "latitude" to location.latitude,
                "longitude" to location.longitude,
                "accuracy" to location.accuracy.toDouble(),
                "mocked" to location.isFromMockProvider,
            ))
            else -> result.error("location", "Location could not be read.", null)
        }
    }

    private fun chooseImage(result: MethodChannel.Result) {
        if (photoResult != null) {
            result.error("photo_busy", "The photo picker is already open.", null)
            return
        }
        photoResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        try {
            startActivityForResult(intent, PHOTO_REQUEST)
        } catch (error: Exception) {
            photoResult = null
            result.error("photo_picker", error.message, null)
        }
    }

    private fun chooseSpreadsheet(result: MethodChannel.Result) {
        if (spreadsheetResult != null) {
            result.error("spreadsheet_busy", "The Excel picker is already open.", null)
            return
        }
        spreadsheetResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        }
        try {
            startActivityForResult(intent, SPREADSHEET_OPEN_REQUEST)
        } catch (error: Exception) {
            spreadsheetResult = null
            result.error("spreadsheet_picker", error.message, null)
        }
    }

    private fun saveSpreadsheet(call: MethodCall, result: MethodChannel.Result) {
        if (spreadsheetSaveResult != null) {
            result.error("spreadsheet_busy", "A spreadsheet save is already open.", null)
            return
        }
        val fileName = call.argument<String>("name") ?: "INDETAIL-attendance.xlsx"
        val encoded = call.argument<String>("base64")
        if (encoded == null) {
            result.error("invalid_arguments", "Spreadsheet content is missing.", null)
            return
        }
        spreadsheetSaveResult = result
        pendingSpreadsheetBase64 = encoded
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        try {
            startActivityForResult(intent, SPREADSHEET_SAVE_REQUEST)
        } catch (error: Exception) {
            spreadsheetSaveResult = null
            pendingSpreadsheetBase64 = null
            result.error("spreadsheet_save", error.message, null)
        }
    }

    @Deprecated("Deprecated by Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SPREADSHEET_OPEN_REQUEST) {
            val result = spreadsheetResult ?: return
            spreadsheetResult = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result.success(null)
                return
            }
            try {
                val uri = data.data!!
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    var total = 0
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_SPREADSHEET_BYTES) throw IllegalArgumentException("Choose an Excel file smaller than 10 MB.")
                        output.write(buffer, 0, read)
                    }
                    output.toByteArray()
                } ?: throw IllegalArgumentException("Could not read the selected Excel file.")
                result.success(mapOf("name" to displayName(uri), "base64" to Base64.encodeToString(bytes, Base64.NO_WRAP)))
            } catch (error: Exception) {
                result.error("spreadsheet_read", error.message, null)
            }
            return
        }
        if (requestCode == SPREADSHEET_SAVE_REQUEST) {
            val result = spreadsheetSaveResult ?: return
            spreadsheetSaveResult = null
            val encoded = pendingSpreadsheetBase64
            pendingSpreadsheetBase64 = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result.success(null)
                return
            }
            try {
                val bytes = Base64.decode(encoded ?: "", Base64.DEFAULT)
                contentResolver.openOutputStream(data.data!!, "w")?.use { it.write(bytes) }
                    ?: throw IllegalArgumentException("Could not save the Excel file.")
                result.success(null)
            } catch (error: Exception) {
                result.error("spreadsheet_save", error.message, null)
            }
            return
        }
        if (requestCode != PHOTO_REQUEST) return
        val result = photoResult ?: return
        photoResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        try {
            val uri = data.data!!
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                var total = 0
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    total += read
                    if (total > MAX_IMAGE_BYTES) throw IllegalArgumentException("Choose an image smaller than 8 MB.")
                    output.write(buffer, 0, read)
                }
                output.toByteArray()
            } ?: throw IllegalArgumentException("Could not read the selected image.")
            result.success(mapOf(
                "name" to displayName(uri),
                "contentType" to (contentResolver.getType(uri) ?: "image/jpeg"),
                "base64" to Base64.encodeToString(bytes, Base64.NO_WRAP),
            ))
        } catch (error: Exception) {
            result.error("photo_read", error.message, null)
        }
    }

    private fun displayName(uri: Uri): String {
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index) ?: "project-photo.jpg"
            }
        } finally {
            cursor?.close()
        }
        return "project-photo.jpg"
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LOCATION_PERMISSION_REQUEST) return
        val result = permissionResult ?: return
        permissionResult = null
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            locationResult = result
            beginLocationUpdates()
        } else {
            result.error("location_permission", "Allow precise location while using INDETAIL to verify this site.", null)
        }
    }

    private fun saveSecure(name: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, masterKey())
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        prefs.edit().putString(name, Base64.encodeToString(cipher.iv + ciphertext, Base64.NO_WRAP)).commit()
    }

    private fun readSecure(name: String): String? {
        val encoded = prefs.getString(name, null) ?: return null
        return try {
            val bytes = Base64.decode(encoded, Base64.NO_WRAP)
            if (bytes.size <= 12) return null
            val iv = bytes.copyOfRange(0, 12)
            val ciphertext = bytes.copyOfRange(12, bytes.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, masterKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (error: Exception) {
            android.util.Log.e("INDETAIL", "readSecure error for $name: ${error.message}")
            null
        }
    }

    private fun masterKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing
        val generator = javax.crypto.KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    companion object {
        private const val KEY_ALIAS = "indetail_device_store_v1"
        private const val LOCATION_PERMISSION_REQUEST = 24017
        private const val PHOTO_REQUEST = 24018
        private const val SPREADSHEET_OPEN_REQUEST = 24019
        private const val SPREADSHEET_SAVE_REQUEST = 24020
        private const val LOCATION_TIMEOUT_MS = 25_000L
        private const val MAX_IMAGE_BYTES = 8 * 1024 * 1024
        private const val MAX_SPREADSHEET_BYTES = 10 * 1024 * 1024
        private val LOCATION_TIMEOUT_TOKEN = Any()
    }
}
