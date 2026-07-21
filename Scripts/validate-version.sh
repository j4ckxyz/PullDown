#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=$(tr -d '[:space:]' < "$repository_root/VERSION")

if ! printf '%s\n' "$version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    printf 'VERSION must contain a stable semantic version in X.Y.Z form; found %s\n' "$version" >&2
    exit 1
fi

project_version=$(awk '$1 == "MARKETING_VERSION:" { print $2; exit }' "$repository_root/project.yml")
if [ "$project_version" != "$version" ]; then
    printf 'VERSION (%s) and project.yml MARKETING_VERSION (%s) must match\n' "$version" "$project_version" >&2
    exit 1
fi

printf 'Validated PullDown version %s\n' "$version"
