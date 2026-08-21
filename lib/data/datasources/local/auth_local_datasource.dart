import 'dart:convert';
import 'dart:math';
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
  static const _keyPasswordSalt = 'auth_password_salt';
  static const _keyRole = 'auth_role';
  static const _keyUserId = 'auth_user_id';
  static const _keyUserMetadata = 'auth_user_metadata';
  static const _keyUsernameToEmail = 'auth_username_to_email';
  static const _keyPendingPassword = 'auth_pending_password';

  // Iteration count for the PBKDF2 KDF below. Chosen as a middle ground for
  // budget Android devices this app targets: a few tens to low hundreds of
  // milliseconds per login, while being orders of magnitude slower to
  // brute-force offline than the single-round HMAC it replaces.
  static const _pbkdf2Iterations = 100000;

  // Helper to generate unique key for each user
  String _getUserKey(String identifier, String key) => '${key}_$identifier';

  String _generateSaltB64() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  // PBKDF2-HMAC-SHA256, single block (32-byte output fits SHA-256's block
  // size exactly, so no multi-block concatenation is needed).
  List<int> _pbkdf2(String password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final result = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  String _hashPasswordWithSalt(String password, String saltB64) {
    final derived = _pbkdf2(password, base64Decode(saltB64), _pbkdf2Iterations);
    return base64Encode(derived);
  }

  Future<String?> getLastUserId() async {
    final email = await _storage.read(key: _keyEmail);
    if (email == null) return null;
    return await _storage.read(key: _getUserKey(email, _keyUserId));
  }

  Future<void> setLastLoggedInEmail(String email) async {
    await _storage.write(key: _keyEmail, value: email.toLowerCase());
  }

  /// Stores the offline-login credentials for [email].
  ///
  /// [markAsLastLoggedIn] must be false when an admin provisions an account for
  /// SOMEONE ELSE. It controls the single `_keyEmail` pointer that
  /// [getLastLoggedInUser] reads, so leaving it true made the admin's own
  /// device "become" the account they had just created: after the next restart,
  /// CheckAuthStatus restored that user instead, silently dropping the admin to
  /// whatever role the new account had.
  Future<void> saveCredentials({
    required String email,
    required String password,
    required String role,
    required String userId,
    required Map<String, dynamic> metadata,
    String? username,
    bool markAsLastLoggedIn = true,
  }) async {
    final normalizedEmail = email.toLowerCase();
    final normalizedUsername = username?.toLowerCase();

    final salt = _generateSaltB64();
    final hash = _hashPasswordWithSalt(password, salt);

    await _storage.write(
      key: _getUserKey(normalizedEmail, _keyPasswordHash),
      value: hash,
    );
    await _storage.write(
      key: _getUserKey(normalizedEmail, _keyPasswordSalt),
      value: salt,
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

    if (markAsLastLoggedIn) {
      await _storage.write(key: _keyEmail, value: normalizedEmail);
    }
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
      final salt = _generateSaltB64();
      final hash = _hashPasswordWithSalt(newPassword, salt);
      await _storage.write(
        key: _getUserKey(normalizedEmail, _keyPasswordHash),
        value: hash,
      );
      await _storage.write(
        key: _getUserKey(normalizedEmail, _keyPasswordSalt),
        value: salt,
      );
    } else if (newEmail != null && normalizedEmail != normalizedCurrentEmail) {
      // Copy old hash + salt to new key
      final oldHash = await _storage.read(
        key: _getUserKey(normalizedCurrentEmail, _keyPasswordHash),
      );
      if (oldHash != null) {
        await _storage.write(
          key: _getUserKey(normalizedEmail, _keyPasswordHash),
          value: oldHash,
        );
      }
      final oldSalt = await _storage.read(
        key: _getUserKey(normalizedCurrentEmail, _keyPasswordSalt),
      );
      if (oldSalt != null) {
        await _storage.write(
          key: _getUserKey(normalizedEmail, _keyPasswordSalt),
          value: oldSalt,
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
      await _storage.delete(
        key: _getUserKey(normalizedCurrentEmail, _keyPasswordSalt),
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
    final storedSalt = await _storage.read(
      key: _getUserKey(email, _keyPasswordSalt),
    );

    bool matched;
    if (storedSalt != null) {
      // Current scheme: PBKDF2-HMAC-SHA256 with a random per-user salt.
      matched = storedHash == _hashPasswordWithSalt(password, storedSalt);
    } else {
      // Legacy schemes (HMAC-SHA256 keyed by the non-secret userId, or
      // even older unsalted SHA-256) -- verify against those, then
      // transparently upgrade to the new PBKDF2 scheme on success so
      // returning users migrate off the weaker hash without needing an
      // explicit password reset.
      final legacySalt = userId ?? email;
      final saltedHash = Hmac(
        sha256,
        utf8.encode(legacySalt),
      ).convert(utf8.encode(password)).toString();
      final unsaltedHash = sha256.convert(utf8.encode(password)).toString();
      matched = storedHash == saltedHash || storedHash == unsaltedHash;

      if (matched) {
        final newSalt = _generateSaltB64();
        await _storage.write(
          key: _getUserKey(email, _keyPasswordHash),
          value: _hashPasswordWithSalt(password, newSalt),
        );
        await _storage.write(
          key: _getUserKey(email, _keyPasswordSalt),
          value: newSalt,
        );
      }
    }

    if (!matched) return null;

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

  /// The last SERVER-CONFIRMED role for [email], as written by
  /// [saveCredentials] / [saveStoredRole]. This is the offline fallback for
  /// authorization decisions -- never `user_metadata`, which the account holder
  /// can rewrite at will through `auth.updateUser()`.
  Future<String?> getStoredRole(String email) {
    return _storage.read(key: _getUserKey(email.toLowerCase(), _keyRole));
  }

  Future<void> saveStoredRole(String email, String role) {
    return _storage.write(
      key: _getUserKey(email.toLowerCase(), _keyRole),
      value: role,
    );
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
