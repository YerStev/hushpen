#!/bin/bash
# Double-click installer: runs scripts/install.sh in a Terminal window.
cd "$(dirname "$0")"
./scripts/install.sh
status=$?
echo
read -r -p "Press Enter to close. " _ || true
exit $status
