#!/bin/bash

# Note that secrets will be masked if printed to the screen (pass --no-masking to disable).

# Usage: ./with-op.sh command and args...
# Usage: ./with-op.sh --no-masking command and args...

op_args=()
if [[ "$1" = "--no-masking" ]]; then
  op_args+=("$1")
  shift
fi

set -- op run "${op_args[@]}" --env-file="${0%/*}/op.env" -- "$@"

echo "> $*" >&2
exec "$@"
