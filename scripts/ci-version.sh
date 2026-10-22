#!/usr/bin/env bash
# Append "+ci<N>" to the top debian/changelog version so every CI rebuild
# is a newer version than what's published (otherwise apt never upgrades).
#   scripts/ci-version.sh <source-tree-with-debian/> <N>
set -euo pipefail
cl="$1/debian/changelog"
sed -i "1s/(\([^)]*\))/(\1+ci$2)/" "$cl"
head -1 "$cl"
