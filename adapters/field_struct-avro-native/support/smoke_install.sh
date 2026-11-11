#!/usr/bin/env bash
# Dev-only: installs a built field_struct-avro-native gem into a throwaway GEM_HOME (with the sibling gems built from
# this repo, since they may not be on RubyGems yet) and runs support/smoke.rb against it.
#   support/smoke_install.sh <path to field_struct-avro-native-*.gem> [scratch dir]
# Set EXPECT_PRECOMPILED=1 to also fail if the install left Rust sources behind (a platform gem has none).
set -euo pipefail
gem_file="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$here/../.." && pwd)"
scratch="${2:-$(mktemp -d)}"
mkdir -p "$scratch/gems-built"
export GEM_HOME="$scratch/home" GEM_PATH="$scratch/home"

(cd "$repo/gems/field_struct" && gem build field_struct.gemspec --output "$scratch/gems-built/field_struct.gem" > /dev/null)
(cd "$repo/adapters/field_struct-avro" && gem build field_struct-avro.gemspec --output "$scratch/gems-built/field_struct-avro.gem" > /dev/null)

gem install --no-document --prerelease \
  "$scratch/gems-built/field_struct.gem" "$scratch/gems-built/field_struct-avro.gem" "$gem_file"

installed="$(ruby -e 'puts Gem::Specification.find_by_name("field_struct-avro-native").gem_dir')"
if [ "${EXPECT_PRECOMPILED:-0}" = "1" ] && find "$installed" -name '*.rs' | grep -q .; then
  echo "FAIL: expected a precompiled gem but Rust sources were installed" >&2
  exit 1
fi

ruby "$here/support/smoke.rb"
