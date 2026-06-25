#!/bin/sh
# Compile the overlay. Needs Xcode command-line tools (`xcode-select --install`).
set -e
cd "$(dirname "$0")"
echo "Compiling overlay (this takes a few seconds)..."
swiftc -O overlay.swift -o aimonitor-overlay
echo "Built ./aimonitor-overlay"
