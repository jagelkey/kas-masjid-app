import 'package:flutter_test/flutter_test.dart';
import 'package:masjid_app/data/datasources/local/app_database.dart';
import 'package:masjid_app/data/datasources/local/auth_local_datasource.dart';
import 'package:masjid_app/domain/entities/user.dart' as domain;
import 'package:masjid_app/domain/repositories/user_repository.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_bloc_update_profile_test.mocks.dart';

@GenerateMocks([AuthLocalDatasource, AppDatabase, UserRepository])
void main() {
  late AuthBloc authBloc;
  late MockAuthLocalDatasource mockLocalDatasource;
  late MockAppDatabase mockAppDatabase;
  late MockUserRepository mockUserRepository;

  setUp(() {
    mockLocalDatasource = MockAuthLocalDatasource();
    mockAppDatabase = MockAppDatabase();
    mockUserRepository = MockUserRepository();

    when(
      mockLocalDatasource.getLastLoggedInUser(),
    ).thenAnswer((_) async => null);

    authBloc = AuthBloc(
      mockLocalDatasource,
      mockAppDatabase,
      mockUserRepository,
    );
  });

  tearDown(() {
    authBloc.close();
  });

  group('UpdateProfileRequested', () {
    const testUserId = 'test-user-id';
    const testEmail = 'test@example.com';
    const testUsername = 'testuser';
    const testFullName = 'Test User';

    final testUser = domain.UserEntity(
      id: 1,
      remoteId: testUserId,
      email: testEmail,
      username: testUsername,
      fullName: testFullName,
      role: 'admin',
      syncStatus: 0,
    );

    test('should emit AuthError when user is not authenticated', () async {
      // Arrange
      authBloc.emit(Unauthenticated());

      // Act & Assert
      final expectation = expectLater(
        authBloc.stream,
        emits(const AuthError('User tidak terautentikasi')),
      );
      authBloc.add(const UpdateProfileRequested(fullName: 'New Name'));
      await expectation;
    });

    test('should emit AuthError when password is too short', () async {
      // Arrange
      final mockUser = User(
        id: testUserId,
        appMetadata: {},
        userMetadata: {
          'full_name': testFullName,
          'username': testUsername,
          'role': 'admin',
        },
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: testEmail,
      );

      authBloc.emit(Authenticated(mockUser, role: UserRole.admin));

      // Act
      authBloc.add(
        const UpdateProfileRequested(
          password: '12345', // Less than 6 characters
        ),
      );

      // Assert
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          const AuthError('Password minimal 6 karakter'),
        ]),
      );
    });

    test('should emit AuthError when email format is invalid', () async {
      // Arrange
      final mockUser = User(
        id: testUserId,
        appMetadata: {},
        userMetadata: {
          'full_name': testFullName,
          'username': testUsername,
          'role': 'admin',
        },
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: testEmail,
      );

      authBloc.emit(Authenticated(mockUser, role: UserRole.admin));

      // Act
      authBloc.add(
        const UpdateProfileRequested(
          email: 'invalidemail', // Invalid format
        ),
      );

      // Assert
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          const AuthError('Format email tidak valid'),
        ]),
      );
    });

    test('should emit AuthError when username is too short', () async {
      // Arrange
      final mockUser = User(
        id: testUserId,
        appMetadata: {},
        userMetadata: {
          'full_name': testFullName,
          'username': testUsername,
          'role': 'admin',
        },
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: testEmail,
      );

      authBloc.emit(Authenticated(mockUser, role: UserRole.admin));

      // Act
      authBloc.add(
        const UpdateProfileRequested(
          username: 'ab', // Less than 3 characters
        ),
      );

      // Assert
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          const AuthError('Username minimal 3 karakter'),
        ]),
      );
    });

    test(
      'should emit AuthError when username contains invalid characters',
      () async {
        // Arrange
        final mockUser = User(
          id: testUserId,
          appMetadata: {},
          userMetadata: {
            'full_name': testFullName,
            'username': testUsername,
            'role': 'admin',
          },
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
          email: testEmail,
        );

        authBloc.emit(Authenticated(mockUser, role: UserRole.admin));

        // Act
        authBloc.add(
          const UpdateProfileRequested(
            username: 'test user', // Contains space
          ),
        );

        // Assert
        await expectLater(
          authBloc.stream,
          emitsInOrder([
            isA<AuthLoading>(),
            const AuthError(
              'Username hanya boleh huruf, angka, dan underscore',
            ),
          ]),
        );
      },
    );

    test('should emit AuthError when email already exists', () async {
      // Arrange
      final mockUser = User(
        id: testUserId,
        appMetadata: {},
        userMetadata: {
          'full_name': testFullName,
          'username': testUsername,
          'role': 'admin',
        },
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: testEmail,
      );

      authBloc.emit(Authenticated(mockUser, role: UserRole.admin));

      when(
        mockUserRepository.getUserByRemoteId(testUserId),
      ).thenAnswer((_) async => testUser);

      when(
        mockUserRepository.getUserByEmail('existing@example.com'),
      ).thenAnswer(
        (_) async => domain.UserEntity(
          id: 2, // Different user
          remoteId: 'other-user-id',
          email: 'existing@example.com',
          username: 'otheruser',
          fullName: 'Other User',
          role: 'viewer',
          syncStatus: 0,
        ),
      );

      // Act
      authBloc.add(const UpdateProfileRequested(email: 'existing@example.com'));

      // Assert
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          const AuthError('Email sudah digunakan user lain'),
        ]),
      );
    });

    test('should emit AuthError when username already exists', () async {
      // Arrange
      final mockUser = User(
        id: testUserId,
        appMetadata: {},
        userMetadata: {
          'full_name': testFullName,
          'username': testUsername,
          'role': 'admin',
        },
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: testEmail,
      );

      authBloc.emit(Authenticated(mockUser, role: UserRole.admin));

      when(
        mockUserRepository.getUserByRemoteId(testUserId),
      ).thenAnswer((_) async => testUser);

      when(mockUserRepository.getUserByUsername('existinguser')).thenAnswer(
        (_) async => domain.UserEntity(
          id: 2, // Different user
          remoteId: 'other-user-id',
          email: 'other@example.com',
          username: 'existinguser',
          fullName: 'Other User',
          role: 'viewer',
          syncStatus: 0,
        ),
      );

      // Act
      authBloc.add(const UpdateProfileRequested(username: 'existinguser'));

      // Assert
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          const AuthError('Username sudah digunakan user lain'),
        ]),
      );
    });

    test('should successfully update profile in offline mode', () async {
      // Arrange
      final mockLocalUser = LocalUser(
        id: testUserId,
        email: testEmail,
        role: UserRole.admin,
        metadata: {'full_name': testFullName, 'username': testUsername},
      );

      authBloc.emit(AuthOffline(mockLocalUser));

      when(
        mockUserRepository.getUserByRemoteId(testUserId),
      ).thenAnswer((_) async => testUser);

      when(
        mockUserRepository.getUserByEmail(any),
      ).thenAnswer((_) async => null);

      when(
        mockUserRepository.getUserByUsername(any),
      ).thenAnswer((_) async => null);

      when(
        mockUserRepository.updateUser(any),
      ).thenAnswer((_) async => Future.value());

      when(
        mockLocalDatasource.updateProfile(
          currentEmail: anyNamed('currentEmail'),
          newEmail: anyNamed('newEmail'),
          newUsername: anyNamed('newUsername'),
          newFullName: anyNamed('newFullName'),
          newPassword: anyNamed('newPassword'),
          role: anyNamed('role'),
          userId: anyNamed('userId'),
        ),
      ).thenAnswer((_) async => Future.value());

      // Act
      authBloc.add(
        const UpdateProfileRequested(
          fullName: 'Updated Name',
          username: 'updateduser',
        ),
      );

      // Assert
      await expectLater(
        authBloc.stream,
        emitsInOrder([
          isA<AuthLoading>(),
          const AuthSuccess('Profil berhasil diperbarui'),
        ]),
      );

      verify(mockUserRepository.updateUser(any)).called(1);
      verify(
        mockLocalDatasource.updateProfile(
          currentEmail: anyNamed('currentEmail'),
          newEmail: anyNamed('newEmail'),
          newUsername: anyNamed('newUsername'),
          newFullName: anyNamed('newFullName'),
          newPassword: anyNamed('newPassword'),
          role: anyNamed('role'),
          userId: anyNamed('userId'),
        ),
      ).called(1);
    });
  });
}
