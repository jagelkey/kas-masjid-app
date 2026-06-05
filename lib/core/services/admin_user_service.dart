import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AdminUserFailureKind { offline, backendUnavailable, failed }

class AdminUserResult {
  final bool isSuccess;
  final String? userId;
  final String? updatedAt;
  final String? message;
  final AdminUserFailureKind? failureKind;

  const AdminUserResult({
    required this.isSuccess,
    this.userId,
    this.updatedAt,
    this.message,
    this.failureKind,
  });

  factory AdminUserResult.success({String? userId, String? updatedAt}) {
    return AdminUserResult(
      isSuccess: true,
      userId: userId,
      updatedAt: updatedAt,
    );
  }

  factory AdminUserResult.failure(
    String message, {
    AdminUserFailureKind kind = AdminUserFailureKind.failed,
  }) {
    return AdminUserResult(
      isSuccess: false,
      message: message,
      failureKind: kind,
    );
  }

  bool get isBackendUnavailable =>
      failureKind == AdminUserFailureKind.backendUnavailable;
}

class AdminUserService {
  final SupabaseClient? _client;

  const AdminUserService(this._client);

  bool get canInvoke {
    final client = _client;
    if (client == null) return false;
    return client.auth.currentSession != null;
  }

  Future<AdminUserResult> createUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? username,
  }) {
    return _invoke(
      action: 'create',
      payload: {
        'email': email,
        'password': password,
        'full_name': fullName,
        'username': username,
        'role': role,
      },
    );
  }

  Future<AdminUserResult> updateUser({
    required String userId,
    required String email,
    required String fullName,
    required String role,
    String? username,
    String? password,
  }) {
    return _invoke(
      action: 'update',
      payload: {
        'user_id': userId,
        'email': email,
        'password': password,
        'full_name': fullName,
        'username': username,
        'role': role,
      },
    );
  }

  Future<AdminUserResult> deleteUser(String userId) {
    return _invoke(action: 'delete', payload: {'user_id': userId});
  }

  Future<AdminUserResult> _invoke({
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) {
      return AdminUserResult.failure(
        'Admin user backend tidak tersedia dalam mode offline',
        kind: AdminUserFailureKind.offline,
      );
    }

    try {
      final response = await client.functions.invoke(
        'admin-users',
        body: {'action': action, ...payload},
      );

      final data = response.data;
      if (data is Map) {
        final success = data['success'] == true;
        if (success) {
          return AdminUserResult.success(
            userId: data['user_id']?.toString(),
            updatedAt: data['updated_at']?.toString(),
          );
        }
        return AdminUserResult.failure(
          data['error']?.toString() ?? 'Operasi admin user gagal',
        );
      }

      return AdminUserResult.failure('Response admin user tidak valid');
    } on FunctionException catch (e) {
      debugPrint('Admin user function failed: $e');
      if (_isMissingFunction(e)) {
        return AdminUserResult.failure(
          'Edge Function admin-users belum deploy. Operasi pengguna ditunda.',
          kind: AdminUserFailureKind.backendUnavailable,
        );
      }
      return AdminUserResult.failure('Admin user backend gagal dipanggil: $e');
    } catch (e) {
      debugPrint('Admin user function failed: $e');
      return AdminUserResult.failure(
        'Admin user backend belum tersedia atau gagal dipanggil: $e',
      );
    }
  }

  bool _isMissingFunction(FunctionException e) {
    if (e.status == 404) return true;
    final details = e.details;
    if (details is Map && details['code'] == 'NOT_FOUND') return true;
    return e.reasonPhrase?.toLowerCase() == 'not found';
  }
}
