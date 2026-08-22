# Runtime adapter contract

A runtime adapter derives a runtime-specific output from an immutable canonical
release. It is not a source of release content or identity.

## Boundary

- `SkillRevision.id` is the sole `release_id`.
- The immutable `SkillRevisionArtifact`/canonical package is the sole canonical
  content source; adapters must not rewrite `SKILL.md`, fixtures, or release
  package bytes.
- Every successful `AdapterArtifact` carries `release_id`, `canonical_hash`,
  `runtime`, `adapter`, `adapter_version`, `contract_version`, and
  `output_hash`.
- The API-owned `CompatibilityMatrix` is runtime metadata only. It does not
  accept release content and an adapter must consume the authoritative matrix,
  never a Plugin-local policy copy.
- An `AdapterFailure` is an adapter result, not a release transition. It never
  marks, mutates, invalidates, publishes, or partially installs the canonical
  release.

## Plugin distribution

The Plugin only loads or distributes a successful artifact. MCP-backed agents
must reference the canonical API source without materializing a local skill
copy. Disk-backed outputs need release/hash/adapter/runtime markers and must
be written atomically. Disk materialization requires Linux, Python 3 and libc
`renameat2(RENAME_EXCHANGE)`; it fails closed before staging when unavailable.
`ALLYE_PYTHON_BIN` may select the Python executable used for capability checks.
Pi uses its official package by default; a local source is an explicit
development opt-in.
