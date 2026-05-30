#!/bin/bash

# Run All Tests Script for Profile Update Feature
# This script runs all unit tests, widget tests, and generates coverage report

echo "========================================="
echo "Running All Tests for Profile Update"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Flutter is installed
if ! command -v flutter &> /dev/null
then
    echo -e "${RED}Flutter is not installed or not in PATH${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Cleaning previous build...${NC}"
flutter clean
echo ""

echo -e "${YELLOW}Step 2: Getting dependencies...${NC}"
flutter pub get
echo ""

echo -e "${YELLOW}Step 3: Generating mocks...${NC}"
flutter pub run build_runner build --delete-conflicting-outputs
echo ""

echo -e "${YELLOW}Step 4: Running all tests...${NC}"
flutter test --coverage
TEST_EXIT_CODE=$?
echo ""

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
else
    echo -e "${RED}✗ Some tests failed!${NC}"
    exit $TEST_EXIT_CODE
fi

echo ""
echo -e "${YELLOW}Step 5: Generating coverage report...${NC}"

# Check if lcov is installed
if command -v lcov &> /dev/null
then
    # Remove generated files from coverage
    lcov --remove coverage/lcov.info \
        '**/*.g.dart' \
        '**/*.freezed.dart' \
        '**/main.dart' \
        '**/firebase_options.dart' \
        --output-file coverage/lcov.info
    
    # Generate HTML report
    genhtml coverage/lcov.info --output-directory coverage/html
    
    echo -e "${GREEN}✓ Coverage report generated at coverage/html/index.html${NC}"
    echo ""
    echo "To view the report, open: coverage/html/index.html"
else
    echo -e "${YELLOW}⚠ lcov not installed. Skipping HTML coverage report.${NC}"
    echo "Install lcov to generate HTML coverage reports:"
    echo "  - Ubuntu/Debian: sudo apt-get install lcov"
    echo "  - macOS: brew install lcov"
fi

echo ""
echo "========================================="
echo -e "${GREEN}Test Suite Completed Successfully!${NC}"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Unit Tests: ✓"
echo "  - Widget Tests: ✓"
echo "  - Coverage Report: Generated"
echo ""
echo "Next steps:"
echo "  1. Review coverage report"
echo "  2. Run manual tests (see MANUAL_TEST_GUIDE.md)"
echo "  3. Deploy to staging"
echo ""

exit 0
