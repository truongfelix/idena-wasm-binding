# Idena Wasm Binding

## Research disclaimer

This is experimental research software. I cannot guarantee its security, correctness, or fitness for any purpose. Use it at your own risk, take responsibility for your decisions, independently verify changes, and stay vigilant.

Go bindings and platform static libraries for the Idena smart-contract
runtime.

[![Test Idena-wasm-binding](https://github.com/truongfelix/idena-wasm-binding/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/truongfelix/idena-wasm-binding/actions/workflows/main.yml)

> This repository is a versioned bridge between consensus-sensitive Rust and
> Go code. It has no independent binary release. Use the exact revision pinned
> by the consuming `idena-go` source, not an arbitrary branch snapshot.

## Artifact provenance

The checked-in archives are built by the pinned `idena-wasm` GitHub workflow.
Their source revisions and toolchain are recorded in `lib/ARTIFACTS_SOURCE`,
and every file is covered by `lib/SHA256SUMS`.

The current artifact set contains:

- Linux x64 and ARM64
- macOS x64 and ARM64
- Windows x64

### What was updated

- The module and CI now use Go `1.26.5` on current Linux, macOS, and Windows
  runners.
- Static archives are imported only from a successful workflow with expected
  idena-wasm and Wasmer revisions and matching runner-produced checksums.
- Tests verify every checked-in archive against the local checksum manifest.
- Extracted binary strings are scanned for credentials and other secret-like
  material before the archives are accepted.
- Go formatting, vet, tests, and `govulncheck` run across the supported host
  matrix.

### Benefits

- Reproducible provenance for otherwise opaque native archives.
- Early detection of stale, substituted, corrupted, or credential-bearing
  artifacts.
- One reviewed ABI and runtime set shared by node, desktop, and contract tests.

### Risks and tradeoffs

- Checksums prove file identity, not correctness or absence of exploitable
  native code. The producing source and workflow still require review.
- The Go API, generated protobuf models, callbacks, and static archive must stay
  ABI-compatible. Updating only one side can cause crashes, memory corruption,
  or different contract execution.
- Archives cannot be reused across operating systems or architectures. Windows
  additionally depends on the expected GNU toolchain linkage.
- Binary secret scanning is heuristic. It reduces accidental leakage but cannot
  prove that an archive contains no sensitive or malicious data.

## Validate locally

Use Go `1.26.5` and the native toolchain for the host:

```bash
go test ./...
go vet ./...
go tool govulncheck ./...
scripts/check-wasm-artifact-secrets.sh
```

## Refresh artifacts

To refresh all supported platforms from a successful `idena-wasm` Build run:

```bash
scripts/update-wasm-artifacts.sh <workflow-run-id> <expected-idena-wasm-revision> <expected-wasmer-revision>
```

The importer requires the GitHub CLI, Cargo, and `jq`. It rejects unsuccessful
or unexpected revisions, verifies the pinned Wasmer source and each
runner-produced checksum before copying any archive, and regenerates the local
manifest. Commit the source record, checksums, and all archives together.

## Compatibility rule

Advance the runtime in this order: Wasmer fork, idena-wasm, binding artifacts,
then idena-go and desktop source manifests. Run smart-contract fixtures and the
full node suite before distributing the resulting node. Reversing or partially
applying that order creates an unreviewed runtime combination.
