import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart'; // For UserRole enum

@lazySingleton
class AuthLocalDatasource {
  final FlutterSecureStorage _storage;

  AuthLocalDatasource()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          resetOnError: true,
          sharedPreferencesName: 'FlutterSecureStorage',
          preferencesKeyPrefix: 'FlutterSecureStorage',
        ),
      );

  static const _keyEmail = 'auth_email';
  static const _keyPasswordHash = 'auth_password_hash';
  static const _keyRole = 'auth_role';
  static const _keyUserId = 'auth_user_id';
  static const _keyUserMetadata = 'auth_user_metadata';
  static const _keyUsernameToEmail = 'auth_username_to_email';
  static const _keyPendingPassword = 'auth_pending_password';

  // Helper to generate unique key for each user
  String _getUserKey(String identifier, String key) => '${key}_$identifier';

  Future<String?> getLastUserId() async {
    final email = await _storage.read(key: _keyEmail);
    if (email == null) return null;
    return await _storage.read(key: _getUserKey(email, _keyUserId));
  }

  Future<void> setLastLoggedInEmail(String email) async {
    await _storage.write(key: _keyEmail, value: email.toLowerCase());
  }

  Future<void> saveCredentials({
    required String email,
    required String password,
    required String role,
    required String userId,
    required Map<String, dynamic> metadata,
    String? username,
  }) async {
    final normalizedEmail = email.toLowerCase();
    final normalizedUsername = username?.toLowerCase();

    // Use userId as salt for hashing
    final hmacSha256 = Hmac(sha256, utf8.encode(userId));
    final hash = hmacSha256.convert(utf8.encode(password)).toString();

    await _storage.write(
      key: _getUserKey(normalizedEmail, _keyPasswordHash),
      value: hash,
    );
    await _storage.write(
      key: _getUserKey(normalizedEmail, _keyRole),
      value: role,
    );
    await _storage.write(
      key: _getUserKey(normalizedEmail, _keyUserId),
      value: userId,
    );
    await _storage.write(
      key: _getUserKey(normalizedEmail, _keyUserMetadata),
      value: jsonEncode(metadata),
    );

    if (normalizedUsername != null && normalizedUsername.isNotEmpty) {
      await _storage.write(
        key: _getUserKey(normalizedUsername, _keyUsernameToEmail),
        value: normalizedEmail,
      );
    }

    await _storage.write(key: _keyEmail, value: normalizedEmail);
  }

  Future<void> updateProfile({
    required String currentEmail,
    String? newEmail,
    String? newUsername,
    String? newFullName,
    String? newPassword, // Raw password
    required String role,
    required String userId,
  }) async {
    final email = newEmail ?? currentEmail;
    final normalizedEmail = email.toLowerCase();
    final normalizedCurrentEmail = currentEmail.toLowerCase();

    // Get old username for cleanup
    final oldMetadataStr = await _storage.read(
      key: _getUserKey(normalizedCurrentEmail, _keyUserMetadata),
    );
    String? oldUsername;
    if (oldMetadataStr != null) {
      try {
        final oldMetadata = jsonDecode(oldMetadataStr);
        oldUsername = oldMetadata['username'] as String?;
      } catch (_) {}
    }

    // 1. Handle Password Transfer/Update
    if (newPassword != null) {
      final hmacSha256 = Hmac(sha256, utf8.encode(userId));
      final hash = hmacSha256.convert(utf8.encode(newPassword)).toString();
      await _storage.write(
        key: _getUserKey(normalizedEmail, _keyPasswordHash),
        value: hash,
      );
    } else if (newEmail != null && normalizedEmail != normalizedCurrentEmail) {
      // Copy old hash to new key
      final oldHash = await _storage.read(
        key: _getUserKey(normalizedCurrentEmail, _keyPasswordHash),
      );
      if (oldHash != null) {
        await _storage.write(
          key: _getUserKey(normalizedEmail, _keyPasswordHash),
          value: oldHash,
        );
      }
    }

    // 2. Handle Metadata
    Map<String, dynamic> metadata = {};
    if (oldMetadataStr != null) {
      try {
        metadata = jsonDecode(oldMetadataStr);
      } catch (_) {}
    }
    if (newFullName != null) metadata['full_name'] = newFullName;
    if (newUsername != null) metadata['username'] = newUsername;

    await _storage.write(
      key: _getUserKey(normalizedEmail, _keyUserMetadata),
      value: jsonEncode(metadata),
    );

    // 3. Handle Role & UserId copy if email changed
    if (newEmail != null && normalizedEmail != normalizedCurrentEmail) {
      await _storage.write(
        key: _getUserKey(normalizedEmail, _keyRole),
        value: role,
      );
      await _storage.write(
        key: _getUserKey(normalizedEmail, _keyUserId),
        value: userId,
      );

      // Update global last email
      await setLastLoggedInEmail(normalizedEmail);

      // Cleanup old email credentials
      await _storage.delete(
        key: _getUserKey(normalizedCurrentEmail, _keyPasswordHash),
      );
      await _storage.delete(key: _getUserKey(normalizedCurrentEmail, _keyRole));
      await _storage.delete(
        key: _getUserKey(normalizedCurrentEmail, _keyUserId),
      );
      await _storage.delete(
        key: _getUserKey(normalizedCurrentEmail, _keyUserMetadata),
      );
    }

    // 4. Handle Username Mapping
    if (newUsername != null) {
      final normalizedNewUsername = newUsername.toLowerCase();
      await _storage.write(
        key: _getUserKey(normalizedNewUsername, _keyUsernameToEmail),
        value: normalizedEmail,
      );

      // Cleanup old username mapping if username changed
      if (oldUsername != null &&
          oldUsername.toLowerCase() != normalizedNewUsername) {
        await _storage.delete(
          key: _getUserKey(oldUsername.toLowerCase(), _keyUsernameToEmail),
        );
      }
    }
  }

  Future<void> savePendingUserPassword(String userId, String password) async {
    await _storage.write(
      key: _getUserKey(userId, _keyPendingPassword),
      value: password,
    );
  }

  Future<String?> getPendingUserPassword(String userId) async {
    return await _storage.read(key: _getUserKey(userId, _keyPendingPassword));
  }

  Future<void> deletePendingUserPassword(String userId) async {
    await _storage.delete(key: _getUserKey(userId, _keyPendingPassword));
  }

  Future<LocalUser?> verifyCredentials(
    String identifier,
    String password,
  ) async {
    final normalizedIdentifier = identifier.toLowerCase();
    final resolvedEmail = normalizedIdentifier.contains('@')
        ? normalizedIdentifier
        : await getEmailByUsername(normalizedIdentifier);
    if (resolvedEmail == null) {
      return null;
    }

    final email = resolvedEmail;
    final storedHash = await _storage.read(
      key: _getUserKey(email, _keyPasswordHash),
    );

    if (storedHash == null) {
      final legacyEmail = await _storage.read(key: _keyEmail);
      if (legacyEmail == email) {
        return _verifyLegacyCredentials(email, password);
      }
      return null;
    }

    final userId = await _storage.read(key: _getUserKey(email, _keyUserId));
    final salt = userId ?? email; // Fallback to email if userId is missing
    
    final hmacSha256 = Hmac(sha256, utf8.encode(salt));
    final saltedHash = hmacSha256.convert(utf8.encode(password)).toString();
    final unsaltedHash = sha256.convert(utf8.encode(password)).toString();

    if (storedHash == saltedHash || storedHash == unsaltedHash) {
      if (storedHash == unsaltedHash) {
        await _storage.write(
          key: _getUserKey(email, _keyPasswordHash),
          value: saltedHash,
        );
      }
      final roleStr = await _storage.read(key: _getUserKey(email, _keyRole));
      final metadataStr = await _storage.read(
        key: _getUserKey(email, _keyUserMetadata),
      );

      return LocalUser(
        id: userId ?? 'offline_user',
        email: email,
        role: _parseRole(roleStr),
        metadata: metadataStr != null ? jsonDecode(metadataStr) : {},
      );
    }
    return null;
  }

  Future<String?> getEmailByUsername(String username) async {
    final normalized = username.toLowerCase();
    return _storage.read(key: _getUserKey(normalized, _keyUsernameToEmail));
  }

  Future<LocalUser?> _verifyLegacyCredentials(
    String email,
    String password,
  ) async {
    final storedHash = await _storage.read(key: _keyPasswordHash);
    final bytes = utf8.encode(password);
    final inputHash = sha256.convert(bytes).toString();

    if (storedHash == inputHash) {
      final roleStr = await _storage.read(key: _keyRole);
      final userId = await _storage.read(key: _keyUserId);
      final metadataStr = await _storage.read(key: _keyUserMetadata);

      // Migrate to new format if successful login
      if (roleStr != null && userId != null && metadataStr != null) {
        await saveCredentials(
          email: email,
          password: password,
          role: roleStr,
          userId: userId,
          metadata: jsonDecode(metadataStr),
        );
      }

      return LocalUser(
        id: userId ?? 'offline_user',
        email: email,
        role: _parseRole(roleStr),
        metadata: metadataStr != null ? jsonDecode(metadataStr) : {},
      );
    }
    return null;
  }

  Future<LocalUser?> getLastLoggedInUser() async {
    final email = await _storage.read(key: _keyEmail);
    if (email == null) return null;

    // Try new format
    var roleStr = await _storage.read(key: _getUserKey(email, _keyRole));
    var userId = await _storage.read(key: _getUserKey(email, _keyUserId));
    var metadataStr = await _storage.read(
      key: _getUserKey(email, _keyUserMetadata),
    );

    // Fallback to legacy
    if (roleStr == null) {
      roleStr = await _storage.read(key: _keyRole);
      userId = await _storage.read(key: _keyUserId);
      metadataStr = await _storage.read(key: _keyUserMetadata);
    }

    if (roleStr != null) {
      return LocalUser(
        id: userId ?? 'offline_user',
        email: email,
        role: _parseRole(roleStr),
        metadata: metadataStr != null ? jsonDecode(metadataStr) : {},
      );
    }
    return null;
  }

  Future<void> clearCredentials() async {
    // Only clear the "last logged in" pointer, not the actual user data
    // This allows multi-user switching without data loss
    await _storage.delete(key: _keyEmail);

    // Optionally we could clear everything if "logout" means "forget everything on this device"
    // But usually for multi-user app we might want to keep credentials.
    // For now, let's stick to clearing current session.
  }

  UserRole _parseRole(String? roleStr) {
    if (roleStr == null) return UserRole.viewer;
    switch (roleStr) {
      case 'UserRole.admin':
      case 'admin':
        return UserRole.admin;
      case 'UserRole.ketua':
      case 'ketua':
        return UserRole.ketua;
      case 'UserRole.bendahara':
      case 'bendahara':
        return UserRole.bendahara;
      case 'UserRole.sekretaris':
      case 'sekretaris':
        return UserRole.sekretaris;
      default:
        return UserRole.viewer;
    }
  }
}

class LocalUser {
  final String id;
  final String email;
  final UserRole role;
  final Map<String, dynamic> metadata;

  LocalUser({
    required this.id,
    required this.email,
    required this.role,
    required this.metadata,
  });

  String? get username => metadata['username'] as String?;
}
