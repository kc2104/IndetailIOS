import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'native_bridge.dart';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://hulfgxqbdliaxulqjunj.supabase.co',
);
// Publishable keys are designed for client apps. Never put a service-role key here.
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_a8j5H4qN5qAFE9j5a6Yqdw_YBSxMUEa',
);

bool get isSupabaseConfigured =>
    supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;

class SupabaseApi {
  SupabaseApi(this.session, {this.onSessionUpdated});

  AppSession session;
  final Future<void> Function(AppSession session)? onSessionUpdated;
  final http.Client _http = http.Client();

  Future<AppSession> signIn(String email, String password) async {
    final result = await _request(
      'POST',
      '/auth/v1/token?grant_type=password',
      body: {'email': email, 'password': password},
      useSession: false,
    );
    return _applyAuth(_asMap(result), fallbackIdentifier: email);
  }

  Future<AppSession> signInEmployeeId(
    String employeeId,
    String password,
  ) async {
    final auth = await _invokeEmployeeAuth({
      'action': 'login',
      'employeeId': employeeId,
      'password': password,
    });
    return _applyAuth(auth, fallbackIdentifier: employeeId);
  }

  Future<EmployeeSignupResult> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final result = await _invokeEmployeeAuth({
      'action': 'signup',
      'displayName': displayName,
      'email': email,
      'password': password,
    });
    final employeeId = '${result['employee_id'] ?? ''}';
    if (!RegExp(r'^ids\d{4}$').hasMatch(employeeId)) {
      throw const ApiException(
        'The signup response did not include a valid Employee ID.',
      );
    }
    final auth = _asMap(result['auth']);
    if ('${auth['access_token'] ?? ''}'.isNotEmpty) {
      await _applyAuth(auth, fallbackIdentifier: email, employeeId: employeeId);
    }
    return EmployeeSignupResult(
      employeeId: employeeId,
      confirmationRequired: result['confirmation_required'] == true,
      signedIn: '${auth['access_token'] ?? ''}'.isNotEmpty,
    );
  }

  Future<Map<String, Object?>> _invokeEmployeeAuth(
    Map<String, Object?> payload,
  ) async {
    final result = await _request(
      'POST',
      '/functions/v1/employee-auth',
      body: payload,
      useSession: false,
    );
    return _asMap(result).cast<String, Object?>();
  }

  Future<AppSession> _applyAuth(
    Map<Object?, Object?> auth, {
    required String fallbackIdentifier,
    String? employeeId,
  }) async {
    final user = _asMap(auth['user']);
    final id = '${user['id'] ?? ''}';
    if (id.isEmpty)
      throw const ApiException('The sign-in response did not include a user.');

    session = AppSession(
      name: '${user['email'] ?? fallbackIdentifier}'.split('@').first,
      email:
          '${user['email'] ?? (fallbackIdentifier.contains('@') ? fallbackIdentifier : '')}',
      role: UserRole.employee,
      userId: id,
      employeeId: employeeId ?? '${auth['employee_id'] ?? ''}'.ifEmptyNull,
      accessToken: '${auth['access_token']}',
      refreshToken: '${auth['refresh_token']}',
    );
    await _syncProfile();
    return session;
  }

  Future<void> getCurrentUser() async {
    if (session.accessToken == null) return;
    try {
      await _request('GET', '/auth/v1/user');
    } on ApiException catch (error) {
      if (error.statusCode != 401 || session.refreshToken == null) rethrow;
      final auth = _asMap(
        await _request(
          'POST',
          '/auth/v1/token?grant_type=refresh_token',
          body: {'refresh_token': session.refreshToken},
          useSession: false,
        ),
      );
      session = AppSession(
        name: session.name,
        email: session.email,
        role: session.role,
        userId: session.userId,
        employeeId: session.employeeId,
        accessToken: '${auth['access_token']}',
        refreshToken: '${auth['refresh_token']}',
      );
      await onSessionUpdated?.call(session);
    }
    await _syncProfile();
  }

  Future<void> _syncProfile() async {
    final userId = session.userId;
    if (userId == null)
      throw const ApiException(
        'The signed-in account has no workspace profile.',
      );
    final profile = await _request(
      'GET',
      '/rest/v1/profiles?select=display_name,role,is_active,employee_id&id=eq.$userId&limit=1',
    );
    final rows = _asList(profile);
    if (rows.isEmpty)
      throw const ApiException(
        'No INDETAIL workspace profile is linked to this account. Ask your Admin to check the setup.',
      );
    final row = _asMap(rows.first);
    if (row['is_active'] != true)
      throw const ApiException(
        'This INDETAIL account is inactive. Contact your Admin.',
      );
    final name = '${row['display_name'] ?? ''}'.trim();
    session = AppSession(
      name: name.isEmpty ? session.name : name,
      email: session.email,
      role: roleFromString(row['role']),
      userId: userId,
      employeeId:
          '${row['employee_id'] ?? session.employeeId ?? ''}'.ifEmptyNull,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    await onSessionUpdated?.call(session);
  }

  Future<void> signOut() async {
    if (session.accessToken == null) return;
    try {
      await _request(
        'POST',
        '/auth/v1/logout',
        body: const {},
        retryAfterRefresh: false,
      );
    } catch (_) {
      // Local credentials are cleared by the caller even if the device is offline.
    }
  }

  Future<List<Map<String, Object?>>> select(
    String table, {
    String query = 'select=*',
  }) async {
    final value = await _request('GET', '/rest/v1/$table?$query');
    return _asList(value)
        .map((item) => _asMap(item).cast<String, Object?>())
        .toList();
  }

  Future<dynamic> insert(String table, Map<String, Object?> row) => _request(
    'POST',
    '/rest/v1/$table',
    body: row,
    headers: {'Prefer': 'return=representation'},
  );

  Future<dynamic> patch(
    String table,
    String filter,
    Map<String, Object?> values,
  ) => _request(
    'PATCH',
    '/rest/v1/$table?$filter',
    body: values,
    headers: {'Prefer': 'return=representation'},
  );

  Future<dynamic> rpc(String function, Map<String, Object?> values) =>
      _request('POST', '/rest/v1/rpc/$function', body: values);

  Future<void> upload(
    String bucket,
    String objectPath,
    PickedImage image,
  ) async {
    await _request(
      'POST',
      '/storage/v1/object/$bucket/${Uri.encodeComponent(objectPath)}',
      bytes: image.bytes,
      contentType: image.contentType,
      headers: {'x-upsert': 'false'},
    );
  }

  Future<String> signedObjectUrl(String bucket, String objectPath) async {
    final encodedPath = objectPath
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    final result = _asMap(
      await _request(
        'POST',
        '/storage/v1/object/sign/$bucket/$encodedPath',
        body: {'expiresIn': 3600},
      ),
    );
    final signedPath = '${result['signedURL'] ?? ''}';
    if (signedPath.isEmpty)
      throw const ApiException('Could not create a photo preview link.');
    return signedPath.startsWith('http')
        ? signedPath
        : '$supabaseUrl/storage/v1$signedPath';
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    List<int>? bytes,
    String? contentType,
    Map<String, String> headers = const {},
    String? bearer,
    bool useSession = true,
    bool retryAfterRefresh = true,
  }) async {
    final uri = Uri.parse('$supabaseUrl$path');
    final request = http.Request(method, uri);
    request.headers['apikey'] = supabaseAnonKey;
    // Publishable API keys are opaque identifiers, not JWTs. Send them only
    // in `apikey`; Authorization must carry a real user access token.
    final authorizationToken =
        bearer ?? (useSession ? session.accessToken : null);
    if (authorizationToken != null && authorizationToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $authorizationToken';
    }
    request.headers['Accept'] = 'application/json';
    if (contentType != null) request.headers['Content-Type'] = contentType;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
    }
    request.headers.addAll(headers);

    if (body != null) {
      request.body = jsonEncode(body);
    } else if (bytes != null) {
      request.bodyBytes = bytes;
    }

    final streamedResponse = await _http
        .send(request)
        .timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamedResponse)
        .timeout(const Duration(seconds: 30));
    final raw = response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 &&
          retryAfterRefresh &&
          useSession &&
          session.refreshToken != null &&
          !path.startsWith('/auth/v1/token')) {
        await _refreshSession();
        return _request(
          method,
          path,
          body: body,
          bytes: bytes,
          contentType: contentType,
          headers: headers,
          retryAfterRefresh: false,
        );
      }
      throw ApiException(_errorMessage(raw), statusCode: response.statusCode);
    }
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return raw;
    }
  }

  Future<void> _refreshSession() async {
    final result = _asMap(
      await _request(
        'POST',
        '/auth/v1/token?grant_type=refresh_token',
        body: {'refresh_token': session.refreshToken},
        useSession: false,
        retryAfterRefresh: false,
      ),
    );
    session = AppSession(
      name: session.name,
      email: session.email,
      role: session.role,
      userId: session.userId,
      employeeId: session.employeeId,
      accessToken: '${result['access_token']}',
      refreshToken: '${result['refresh_token']}',
    );
    await onSessionUpdated?.call(session);
  }

  String _errorMessage(String raw) {
    try {
      final data = _asMap(jsonDecode(raw));
      return '${data['message'] ?? data['msg'] ?? data['error_description'] ?? data['error'] ?? raw}';
    } catch (_) {
      return raw.isEmpty ? 'The request failed. Try again.' : raw;
    }
  }
}

class EmployeeSignupResult {
  const EmployeeSignupResult({
    required this.employeeId,
    required this.confirmationRequired,
    required this.signedIn,
  });

  final String employeeId;
  final bool confirmationRequired;
  final bool signedIn;
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

Map<Object?, Object?> _asMap(Object? value) =>
    value is Map ? value.cast<Object?, Object?>() : <Object?, Object?>{};

List<Object?> _asList(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

extension _StringNullIfEmpty on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
