# Testing Guide - Profile Update Feature

## Overview

This directory contains all automated tests for the profile update feature, including:

- Unit tests for BLoC logic
- Widget tests for UI components
- Integration tests (if applicable)

## Test Structure

```
test/
├── presentation/
│   ├── blocs/
│   │   └── auth/
│   │       └── auth_bloc_update_profile_test.dart
│   └── pages/
│       └── edit_profile_page_test.dart
├── run_all_tests.sh
└── README.md
```

## Running Tests

### Option 1: Run All Tests (Recommended)

```bash
# Make script executable (first time only)
chmod +x test/run_all_tests.sh

# Run all tests with coverage
./test/run_all_tests.sh
```

This will:

1. Clean previous builds
2. Get dependencies
3. Generate mocks
4. Run all tests
5. Generate coverage report

### Option 2: Run Specific Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/presentation/blocs/auth/auth_bloc_update_profile_test.dart

# Run tests with coverage
flutter test --coverage

# Run tests in watch mode (auto-rerun on changes)
flutter test --watch
```

### Option 3: Run Tests in VS Code

1. Install "Flutter" extension
2. Open test file
3. Click "Run" or "Debug" above test functions

## Test Coverage

### Current Coverage

Run tests with coverage to see current coverage:

```bash
flutter test --coverage
```

View HTML coverage report:

```bash
# Generate HTML report (requires lcov)
genhtml coverage/lcov.info -o coverage/html

# Open in browser
open coverage/html/index.html  # macOS
xdg-open coverage/html/index.html  # Linux
start coverage/html/index.html  # Windows
```

### Coverage Goals

- **Unit Tests:** > 80% coverage
- **Widget Tests:** > 70% coverage
- **Overall:** > 75% coverage

## Test Categories

### 1. Unit Tests (BLoC)

**File:** `test/presentation/blocs/auth/auth_bloc_update_profile_test.dart`

**Tests:**

- ✅ User not authenticated error
- ✅ Password too short validation
- ✅ Invalid email format validation
- ✅ Username too short validation
- ✅ Username invalid characters validation
- ✅ Email already exists validation
- ✅ Username already exists validation
- ✅ Successful profile update (offline mode)

**Run:**

```bash
flutter test test/presentation/blocs/auth/auth_bloc_update_profile_test.dart
```

### 2. Widget Tests (UI)

**File:** `test/presentation/pages/edit_profile_page_test.dart`

**Tests:**

- ✅ Display all form fields
- ✅ Load user data on init
- ✅ Validation error for empty full name
- ✅ Validation error for invalid username
- ✅ Validation error for short username
- ✅ Validation error for invalid email
- ✅ Show confirmation dialog
- ✅ Show password warning in dialog
- ✅ Show snackbar for no changes

**Run:**

```bash
flutter test test/presentation/pages/edit_profile_page_test.dart
```

## Writing New Tests

### Unit Test Template

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([YourDependency])
void main() {
  late YourClass classUnderTest;
  late MockYourDependency mockDependency;

  setUp(() {
    mockDependency = MockYourDependency();
    classUnderTest = YourClass(mockDependency);
  });

  tearDown(() {
    // Cleanup if needed
  });

  group('YourFeature', () {
    test('should do something', () {
      // Arrange
      when(mockDependency.method()).thenReturn(expectedValue);

      // Act
      final result = classUnderTest.doSomething();

      // Assert
      expect(result, expectedValue);
      verify(mockDependency.method()).called(1);
    });
  });
}
```

### Widget Test Template

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: YourWidget(),
    );
  }

  group('YourWidget Tests', () {
    testWidgets('should display something', (WidgetTester tester) async {
      // Arrange & Act
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Expected Text'), findsOneWidget);
    });
  });
}
```

## Mocking

### Generate Mocks

```bash
# Generate mocks for all @GenerateMocks annotations
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode (auto-regenerate on changes)
flutter pub run build_runner watch --delete-conflicting-outputs
```

### Mock Dependencies

Common mocks used in tests:

- `MockAuthBloc` - For testing widgets that depend on AuthBloc
- `MockAuthLocalDatasource` - For testing local storage operations
- `MockUserRepository` - For testing database operations
- `MockAppDatabase` - For testing database interactions

## Debugging Tests

### Print Debug Info

```dart
test('should do something', () {
  // Print debug info
  print('Debug: $someValue');
  debugPrint('Debug: $someValue'); // Better for Flutter

  // Your test code
});
```

### Run Single Test

```dart
test('should do something', () {
  // Your test
}, skip: false); // Set to true to skip this test

// Or use testWidgets for widget tests
testWidgets('should display something', (tester) async {
  // Your test
}, skip: false);
```

### Debug in VS Code

1. Set breakpoint in test file
2. Click "Debug" above test function
3. Use debug controls to step through code

## Common Issues

### Issue 1: Mock Generation Fails

**Solution:**

```bash
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Issue 2: Tests Timeout

**Solution:**

```dart
testWidgets('should do something', (tester) async {
  // Your test
}, timeout: const Timeout(Duration(seconds: 30)));
```

### Issue 3: Widget Not Found

**Solution:**

```dart
// Wait for animations to complete
await tester.pumpAndSettle();

// Or pump specific number of times
await tester.pump(const Duration(seconds: 1));
```

### Issue 4: Async Tests Fail

**Solution:**

```dart
test('should do async operation', () async {
  // Use async/await
  final result = await asyncOperation();
  expect(result, expectedValue);
});
```

## Best Practices

### 1. Test Naming

```dart
// Good
test('should return user when credentials are valid', () {});

// Bad
test('test1', () {});
```

### 2. Arrange-Act-Assert Pattern

```dart
test('should do something', () {
  // Arrange - Set up test data and mocks
  when(mock.method()).thenReturn(value);

  // Act - Execute the code under test
  final result = classUnderTest.doSomething();

  // Assert - Verify the results
  expect(result, expectedValue);
});
```

### 3. One Assertion Per Test

```dart
// Good
test('should return correct name', () {
  expect(user.name, 'John');
});

test('should return correct email', () {
  expect(user.email, 'john@example.com');
});

// Avoid (unless related)
test('should return correct user data', () {
  expect(user.name, 'John');
  expect(user.email, 'john@example.com');
  expect(user.age, 30);
});
```

### 4. Use setUp and tearDown

```dart
group('UserService', () {
  late UserService service;
  late MockRepository mockRepo;

  setUp(() {
    mockRepo = MockRepository();
    service = UserService(mockRepo);
  });

  tearDown(() {
    // Cleanup if needed
  });

  test('test 1', () {});
  test('test 2', () {});
});
```

### 5. Test Edge Cases

```dart
group('Email Validation', () {
  test('should accept valid email', () {});
  test('should reject email without @', () {});
  test('should reject email without domain', () {});
  test('should reject empty email', () {});
  test('should reject null email', () {});
});
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: "3.x"
      - run: flutter pub get
      - run: flutter pub run build_runner build --delete-conflicting-outputs
      - run: flutter test --coverage
      - uses: codecov/codecov-action@v2
        with:
          files: ./coverage/lcov.info
```

## Resources

- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [Mockito Documentation](https://pub.dev/packages/mockito)
- [BLoC Testing](https://bloclibrary.dev/#/testing)
- [Widget Testing](https://docs.flutter.dev/cookbook/testing/widget/introduction)

## Support

For issues or questions:

1. Check this README
2. Check Flutter testing docs
3. Ask in team chat
4. Create an issue in repository

---

**Last Updated:** 2024-02-24  
**Maintainer:** Development Team
