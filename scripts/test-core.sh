#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -O PianoBloom/PitchCore.swift PianoBloom/PolyphonicCore.swift PianoBloom/ScoreCore.swift PianoBloom/HanonScores.swift Tests/main.swift -o "$test_dir/core-tests"
"$test_dir/core-tests"
