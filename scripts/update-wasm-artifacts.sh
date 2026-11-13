#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <workflow-run-id> <expected-idena-wasm-revision> <expected-wasmer-revision>" >&2
  exit 2
fi

run_id="$1"
expected_revision="$2"
expected_wasmer_revision="$3"
wasm_repo="${IDENA_WASM_REPO:-truongfelix/idena-wasm}"
wasmer_repo="${IDENA_WASMER_REPO:-truongfelix/wasmer}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

actual_revision="$(gh run view "${run_id}" --repo "${wasm_repo}" --json headSha --jq .headSha)"
conclusion="$(gh run view "${run_id}" --repo "${wasm_repo}" --json conclusion --jq .conclusion)"

if [[ "${conclusion}" != "success" ]]; then
  echo "workflow run ${run_id} did not succeed: ${conclusion}" >&2
  exit 1
fi
if [[ "${actual_revision}" != "${expected_revision}" ]]; then
  echo "workflow run revision ${actual_revision} does not match ${expected_revision}" >&2
  exit 1
fi
if [[ ! "${expected_wasmer_revision}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "invalid expected Wasmer revision: ${expected_wasmer_revision}" >&2
  exit 1
fi

cargo_source="${tmp_dir}/idena-wasm-source"
mkdir -p "${cargo_source}/src"
gh api \
  -H "Accept: application/vnd.github.raw+json" \
  "repos/${wasm_repo}/contents/Cargo.toml?ref=${actual_revision}" > "${cargo_source}/Cargo.toml"
gh api \
  -H "Accept: application/vnd.github.raw+json" \
  "repos/${wasm_repo}/contents/Cargo.lock?ref=${actual_revision}" > "${cargo_source}/Cargo.lock"
: > "${cargo_source}/src/lib.rs"

actual_wasmer_revision="$(
  cargo metadata \
    --manifest-path "${cargo_source}/Cargo.toml" \
    --locked \
    --no-deps \
    --format-version 1 |
    jq -er --arg source "git+https://github.com/${wasmer_repo}?rev=" '
      [.packages[0].dependencies[]
        | select(.source | startswith($source))
        | .source
        | capture("[?]rev=(?<revision>[0-9a-f]{40})$").revision]
      | unique
      | if length == 1 then .[0]
        else error("expected one pinned Wasmer revision in idena-wasm metadata")
        end
    '
)"
if [[ "${actual_wasmer_revision}" != "${expected_wasmer_revision}" ]]; then
  echo "idena-wasm pins Wasmer ${actual_wasmer_revision}, not ${expected_wasmer_revision}" >&2
  exit 1
fi

gh run download "${run_id}" --repo "${wasm_repo}" --dir "${tmp_dir}"

artifacts=(
  "linux-x64:libidena_wasm_linux_amd64.a"
  "linux-arm64:libidena_wasm_linux_aarch64.a"
  "macos-x64:libidena_wasm_darwin_amd64.a"
  "macos-arm64:libidena_wasm_darwin_arm64.a"
  "windows-x64:libidena_wasm_windows_amd64.a"
)

checksums_file="${tmp_dir}/SHA256SUMS"
: > "${checksums_file}"

for entry in "${artifacts[@]}"; do
  artifact_group="${entry%%:*}"
  artifact_name="${entry#*:}"
  artifact_path="${tmp_dir}/${artifact_group}/${artifact_name}"
  checksum_path="${artifact_path}.sha256"

  if [[ ! -f "${artifact_path}" || ! -f "${checksum_path}" ]]; then
    echo "missing artifact or checksum for ${artifact_name}" >&2
    exit 1
  fi

  expected_checksum="$(awk 'NR == 1 {print $1}' "${checksum_path}")"
  actual_checksum="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
  if [[ ! "${expected_checksum}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "invalid checksum file for ${artifact_name}" >&2
    exit 1
  fi
  if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
    echo "checksum mismatch for ${artifact_name}" >&2
    exit 1
  fi

  install -m 0644 "${artifact_path}" "${root_dir}/lib/${artifact_name}"
  printf '%s  %s\n' "${actual_checksum}" "${artifact_name}" >> "${checksums_file}"
done

install -m 0644 "${checksums_file}" "${root_dir}/lib/SHA256SUMS"

cat > "${tmp_dir}/ARTIFACTS_SOURCE" <<EOF
repository=https://github.com/${wasm_repo}
idena_wasm_revision=${actual_revision}
workflow_run=${run_id}
rust_toolchain=1.97.0
wasmer_revision=${actual_wasmer_revision}
EOF
install -m 0644 "${tmp_dir}/ARTIFACTS_SOURCE" "${root_dir}/lib/ARTIFACTS_SOURCE"

echo "Updated ${#artifacts[@]} verified archives from run ${run_id}."
