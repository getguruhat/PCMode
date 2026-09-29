#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/WinApp/PressGate.swift Sources/WinApp/CutState.swift Sources/WinApp/DeleteKey.swift Sources/WinApp/SwitcherNavigation.swift Tests/main.swift -o "$TEST_DIR/press-tests"
"$TEST_DIR/press-tests"
