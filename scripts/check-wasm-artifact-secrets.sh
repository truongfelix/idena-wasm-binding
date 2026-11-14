#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

for tool in gitleaks strings awk; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "required command not found: ${tool}" >&2
    exit 1
  fi
done

archives=("${root_dir}"/lib/*.a)
if [[ ! -e "${archives[0]}" ]]; then
  echo "no static library artifacts found" >&2
  exit 1
fi

for archive in "${archives[@]}"; do
  output="${tmp_dir}/$(basename "${archive}").strings"
  # The first line is text: the strings start with the archive's own "!<arch>", and gitleaks skips a file it takes
  # for an archive as binary.
  {
    printf 'strings of %s\n' "$(basename "${archive}")"
    # Keep unrelated binary strings from forming a synthetic key/value match.
    strings "${archive}" |
      awk '{print $0 " __GITLEAKS_STRING_BOUNDARY__"}'
  } > "${output}"
done

expected_bytes="$(cat "${tmp_dir}"/*.strings | wc -c | tr -d ' ')"
log_file="$(mktemp)"
trap 'rm -rf "${tmp_dir}" "${log_file}"' EXIT
status=0
gitleaks dir "${tmp_dir}" --redact --no-banner 2> "${log_file}" || status=$?
cat "${log_file}" >&2
if [[ "${status}" -ne 0 ]]; then
  exit "${status}"
fi
# A file gitleaks skips passes silently: every byte written must have been scanned.
scanned_bytes="$(grep -oE 'scanned ~[0-9]+ bytes' "${log_file}" | grep -oE '[0-9]+' || true)"
if [[ "${scanned_bytes}" != "${expected_bytes}" ]]; then
  echo "gitleaks scanned ${scanned_bytes:-no} bytes of ${expected_bytes}" >&2
  exit 1
fi
