import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masjid_app/presentation/blocs/auth/auth_bloc.dart';
import 'package:masjid_app/presentation/pages/edit_profile_page.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'edit_profile_page_test.mocks.dart';

@GenerateMocks([AuthBloc])
void main() {
  late MockAuthBloc mockAuthBloc;

  setUp(() {
    mockAuthBloc = MockAuthBloc();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: BlocProvider<AuthBloc>.value(
        value: mockAuthBloc,
        child: const EditProfilePage(),
      ),
    );
  }

  group('EditProfilePage Widget Tests', () {
    testWidgets('should display all form fields', (WidgetTester tester) async {
      // Arrange
      final mockUser = User(
        id: 'test-id',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User', 'username': 'testuser'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'test@example.com',
      );

      when(
        mockAuthBloc.state,
      ).thenReturn(Authenticated(mockUser, role: UserRole.admin));
      when(mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(Authenticated(mockUser, role: UserRole.admin)),
      );

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Edit Profil'), findsOneWidget);
      expect(find.text('Nama Lengkap'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password Baru'), findsOneWidget);
      expect(find.text('Konfirmasi Password Baru'), findsOneWidget);
      expect(find.text('Simpan Perubahan'), findsOneWidget);
    });

    testWidgets('should load user data on init', (WidgetTester tester) async {
      // Arrange
      final mockUser = User(
        id: 'test-id',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User', 'username': 'testuser'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'test@example.com',
      );

      when(
        mockAuthBloc.state,
      ).thenReturn(Authenticated(mockUser, role: UserRole.admin));
      when(mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(Authenticated(mockUser, role: UserRole.admin)),
      );

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('testuser'), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('should show validation error for empty full name', (
      WidgetTester tester,
    ) async {
      // Arrange
      final mockUser = User(
        id: 'test-id',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User', 'username': 'testuser'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'test@example.com',
      );

      when(
        mockAuthBloc.state,
      ).thenReturn(Authenticated(mockUser, role: UserRole.admin));
      when(mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(Authenticated(mockUser, role: UserRole.admin)),
      );

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Clear full name field
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Test User'),
        '',
      );

      // Tap save button
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Wajib diisi'), findsOneWidget);
    });

    testWidgets('should show validation error for invalid username', (
      WidgetTester tester,
    ) async {
      // Arrange
      final mockUser = User(
        id: 'test-id',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User', 'username': 'testuser'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'test@example.com',
      );

      when(
        mockAuthBloc.state,
      ).thenReturn(Authenticated(mockUser, role: UserRole.admin));
      when(mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(Authenticated(mockUser, role: UserRole.admin)),
      );

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Enter username with space
      final usernameFinder = find.widgetWithText(TextFormField, 'testuser');
      await tester.enterText(usernameFinder, 'test user');

      // Tap save button
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Tidak boleh ada spasi'), findsOneWidget);
    });

    testWidgets('should show validation error for short username', (
      WidgetTester tester,
    ) async {
      // Arrange
      final mockUser = User(
        id: 'test-id',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User', 'username': 'testuser'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'test@example.com',
      );

      when(
        mockAuthBloc.state,
      ).thenReturn(Authenticated(mockUser, role: UserRole.admin));
      when(mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(Authenticated(mockUser, role: UserRole.admin)),
      );

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Enter short username
      final usernameFinder = find.widgetWithText(TextFormField, 'testuser');
      await tester.enterText(usernameFinder, 'ab');

      // Tap save button
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Minimal 3 karakter'), findsOneWidget);
    });

    testWidgets('should show validation error for invalid email', (
      WidgetTester tester,
    ) async {
      // Arrange
      final mockUser = User(
        id: 'test-id',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User', 'username': 'testuser'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'test@example.com',
      );

      when(
        mockAuthBloc.state,
      ).thenReturn(Authenticated(mockUser, role: UserRole.admin));
      when(mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(Authenticated(mockUser, role: UserRole.admin)),
      );

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Enter invalid email
      final emailFinder = find.widgetWithText(
        TextFormField,
        'test@example.com',
      );
      await tester.enterText(emailFinder, 'invalidemail');

      // Tap save button
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Format email tidak valid'), findsOneWidget);
    });

    testWidgets('should show confirmation dialog when saving', (
      WidgetTester tester,
    ) async {
      // Arrange
      final mockUser = User(
        id: 'test-id',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User', 'username': 'testuser'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'test@example.com',
      );

      when(
        mockAuthBloc.state,
      ).thenReturn(Authenticated(mockUser, role: UserRole.admin));
      when(mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(Authenticated(mockUser, role: UserRole.admin)),
      );

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Change full name
      final fullNameFinder = find.widgetWithText(TextFormField, 'Test User');
      await tester.enterText(fullNameFinder, 'Updated Name');

      // Tap save button
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Konfirmasi Perubahan'), findsOneWidget);
      expect(
        find.text('Apakah Anda yakin ingin menyimpan perubahan ini?'),
        findsOneWidget,
      );
      expect(find.text('Batal'), findsOneWidget);
      expect(find.text('Simpan'), findsOneWidget);
    });

    testWidgets('should show password warning in confirmation dialog', (
      WidgetTester tester,
    ) async {
      // Arrange
      final mockUser = User(
        id: 'test-id',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User', 'username': 'testuser'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'test@example.com',
      );

      when(
        mockAuthBloc.state,
      ).thenReturn(Authenticated(mockUser, role: UserRole.admin));
      when(mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(Authenticated(mockUser, role: UserRole.admin)),
      );

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Enter new password
      final passwordFinder = find.widgetWithText(
        TextFormField,
        'Password Baru',
      );
      await tester.enterText(passwordFinder, 'newpass123');

      final confirmPasswordFinder = find.widgetWithText(
        TextFormField,
        'Konfirmasi Password Baru',
      );
      await tester.enterText(confirmPasswordFinder, 'newpass123');

      // Tap save button
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Password akan diubah'), findsOneWidget);
    });

    testWidgets('should show snackbar for no changes', (
      WidgetTester tester,
    ) async {
      // Arrange
      final mockUser = User(
        id: 'test-id',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User', 'username': 'testuser'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'test@example.com',
      );

      when(
        mockAuthBloc.state,
      ).thenReturn(Authenticated(mockUser, role: UserRole.admin));
      when(mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(Authenticated(mockUser, role: UserRole.admin)),
      );

      // Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap save without making changes
      await tester.tap(find.text('Simpan Perubahan'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Tidak ada perubahan untuk disimpan'), findsOneWidget);
    });
  });
}
