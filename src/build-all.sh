#!/bin/bash

set -euo pipefail

_dir=${BASH_SOURCE%"${BASH_SOURCE##*/}"}
_dir=${_dir:-$PWD}
_dir=$(cd "$_dir" && pwd -P)

shfmt_minify=${shfmt_minify:-0} \
    shfmt_simplify=${shfmt_simplify:-1} \
    "$_dir/build-bash.sh" "$@"

echo >&2

"$_dir/build-json.sh" "$@"
