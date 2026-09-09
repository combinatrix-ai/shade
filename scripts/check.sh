#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift test
./scripts/build.sh
python3 scripts/test-restore-guard.py
git diff --check
