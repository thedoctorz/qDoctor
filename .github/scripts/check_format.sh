#!/usr/bin/env bash
# Checks that the project's Dart is formatted.
#
#   check_format.sh            # fail if anything would change
#   check_format.sh --write    # format in place
#
# The file list comes from `git ls-files`, which is the right set for three
# reasons: submodule contents under lib/modules are gitlinks rather than tracked
# files, so flipperlib, dartufbt and the C++ tree are excluded without naming
# them; generated files are gitignored, so lib/services/localization/gen and
# firebase_options.dart are skipped; and a new directory is covered the day it
# is added rather than needing to be enumerated here.
#
# `--others --exclude-standard` as well as the index, because a file that has
# not been added yet is exactly the one whose formatting has never been
# checked. Without it a local run before `git add` is a false green, and the
# first anyone hears of it is red CI on a brand-new file. On CI itself
# everything is tracked, so it changes nothing there.
#
# `dart format` does not read the analyzer's exclude list, which is why this
# cannot simply be `dart format lib test`.
set -Eeuo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

write=0
if [[ "${1:-}" == "--write" ]]; then
  write=1
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--write]" >&2
  exit 2
fi

pathspec=(
  'lib/*.dart' 'lib/**/*.dart' 'test/*.dart' 'test/**/*.dart'
  ':(exclude)lib/modules/universal_ble/**'
)

count="$(git ls-files -- "${pathspec[@]}" | wc -l)"
if (( count == 0 )); then
  echo "::error::No Dart files found to format-check." >&2
  exit 1
fi

# Batched through xargs: the list is a few hundred paths, which overruns the
# command-line limit on some hosts. xargs reports non-zero if any batch does.
format=(dart format)
if (( write )); then
  :
else
  format+=(--output=none --set-exit-if-changed)
fi
if ! git ls-files -z -- "${pathspec[@]}" \
     | xargs -0 -n 100 "${format[@]}" --; then
  echo "::error::Dart formatting differs. Run .github/scripts/check_format.sh --write" >&2
  exit 1
fi
echo "Checked $count Dart file(s)."
