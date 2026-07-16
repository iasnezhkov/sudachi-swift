# Security Policy

## Supported versions

This project is pre-1.0. Only the latest tagged release receives fixes.

| Version | Supported |
|---------|-----------|
| latest `0.x` | ✅ |
| older      | ❌ |

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report vulnerabilities privately to **iasnezhkov@gmail.com**, or via GitHub's
[private security advisories](https://github.com/iasnezhkov/sudachi-swift/security/advisories/new).

Include, if possible:

- a description of the issue and its impact,
- steps to reproduce (a minimal Swift snippet is ideal),
- the versions of this package, `sudachi.rs`, and the SudachiDict edition you
  used.

You can expect an initial acknowledgement within a few days. Because this is a
volunteer-maintained project, fix timelines are best-effort.

## Scope notes

This package is a thin binding over
[sudachi.rs](https://github.com/WorksApplications/sudachi.rs). Vulnerabilities
in the underlying Rust core or in SudachiDict data should be reported upstream;
report here anything specific to the Swift/FFI wrapper, the build/release
pipeline, or the distributed `xcframework`.
