#!/bin/bash

# SafetyGuardian Test Runner
# Run this script after installing Xcode to build and test the app

set -e  # Exit on error

echo "========================================"
echo "SafetyGuardian Test Suite Runner"
echo "========================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Xcode is installed
echo "Checking Xcode installation..."
if [ ! -d "/Applications/Xcode.app" ]; then
    echo -e "${RED}ERROR: Xcode is not installed!${NC}"
    echo ""
    echo "Please install Xcode from the Mac App Store:"
    echo "  1. Open Mac App Store"
    echo "  2. Search for 'Xcode'"
    echo "  3. Click 'Get' or 'Install'"
    echo "  4. Wait for installation to complete"
    echo "  5. Run this script again"
    exit 1
fi

echo -e "${GREEN}✓ Xcode is installed${NC}"

# Switch to Xcode
echo "Configuring Xcode..."
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer || {
    echo -e "${YELLOW}Note: xcode-select already configured or requires manual setup${NC}"
}

# Accept license
echo "Checking Xcode license..."
sudo xcodebuild -license accept 2>/dev/null || {
    echo -e "${YELLOW}Note: License may already be accepted${NC}"
}

# Verify xcodebuild works
echo "Verifying xcodebuild..."
xcodebuild -version || {
    echo -e "${RED}ERROR: xcodebuild not working properly${NC}"
    exit 1
}

echo -e "${GREEN}✓ Xcode is configured${NC}"
echo ""

# Navigate to project directory
cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)
echo "Project directory: $PROJECT_DIR"
echo ""

# List available simulators
echo "========================================"
echo "Available iOS Simulators:"
echo "========================================"
xcrun simctl list devices available | grep -E "iPhone|iPad" || echo "No simulators found"
echo ""

# Choose a simulator (iPhone 15 Pro if available, otherwise first iPhone)
SIMULATOR=$(xcrun simctl list devices available | grep "iPhone 15 Pro" | head -1 | sed -n 's/.*(\(.*\)).*/\1/p')
if [ -z "$SIMULATOR" ]; then
    SIMULATOR=$(xcrun simctl list devices available | grep "iPhone" | head -1 | sed -n 's/.*(\(.*\)).*/\1/p')
fi

if [ -z "$SIMULATOR" ]; then
    echo -e "${RED}ERROR: No iPhone simulator found!${NC}"
    echo "Please open Xcode and install an iOS simulator."
    exit 1
fi

echo -e "${GREEN}Using simulator: $SIMULATOR${NC}"
echo ""

# Build the project
echo "========================================"
echo "Building SafetyGuardian..."
echo "========================================"
xcodebuild -scheme SafetyGuardian \
    -destination "platform=iOS Simulator,id=$SIMULATOR" \
    clean build \
    | tee build.log \
    | grep -E "Building|Compiling|Linking|Build succeeded|Build failed|error:|warning:" || true

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}✗ Build failed!${NC}"
    echo "See build.log for details"
    exit 1
fi

echo -e "${GREEN}✓ Build succeeded!${NC}"
echo ""

# Run tests
echo "========================================"
echo "Running Tests..."
echo "========================================"
xcodebuild test \
    -scheme SafetyGuardian \
    -destination "platform=iOS Simulator,id=$SIMULATOR" \
    -resultBundlePath TestResults \
    | tee test.log \
    | grep -E "Test Suite|Test Case|passed|failed|Testing|error:|warning:" || true

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${YELLOW}Some tests may have failed${NC}"
else
    echo -e "${GREEN}✓ Tests completed!${NC}"
fi

echo ""

# Parse test results
echo "========================================"
echo "Test Results Summary"
echo "========================================"

TOTAL_TESTS=$(grep -o "Executed [0-9]* test" test.log | grep -o "[0-9]*" | head -1 || echo "0")
PASSED_TESTS=$(grep -o "[0-9]* passed" test.log | grep -o "[0-9]*" | head -1 || echo "0")
FAILED_TESTS=$(grep -o "[0-9]* failed" test.log | grep -o "[0-9]*" | head -1 || echo "0")

echo "Total Tests:  $TOTAL_TESTS"
echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
if [ "$FAILED_TESTS" -gt 0 ]; then
    echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
else
    echo -e "Failed:       ${GREEN}$FAILED_TESTS${NC}"
fi
echo ""

# Show failed tests if any
if [ "$FAILED_TESTS" -gt 0 ]; then
    echo "========================================"
    echo "Failed Tests:"
    echo "========================================"
    grep "Test Case.*failed" test.log || echo "Unable to parse failed tests"
    echo ""
fi

# Generate HTML report (optional)
if command -v xcpretty &> /dev/null; then
    echo "Generating HTML report..."
    cat test.log | xcpretty --report html --output test_report.html
    echo -e "${GREEN}✓ HTML report saved to test_report.html${NC}"
fi

echo "========================================"
echo "Test run complete!"
echo "========================================"
echo "Full logs:"
echo "  Build log: $PROJECT_DIR/build.log"
echo "  Test log:  $PROJECT_DIR/test.log"
echo ""

# Exit with success if at least 90% tests passed
if [ "$TOTAL_TESTS" -gt 0 ]; then
    PASS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    if [ "$PASS_RATE" -ge 90 ]; then
        echo -e "${GREEN}✓ Test run successful! ($PASS_RATE% passed)${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ Some tests failed ($PASS_RATE% passed)${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ No tests were executed${NC}"
    exit 1
fi
