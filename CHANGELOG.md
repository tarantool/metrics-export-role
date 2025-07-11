# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Fixed

### Changed

## 0.3.1 - 2025-07-07

The release contains some minor bugfixes.

### Fixed

- `Address already in use` error on change role's config on the fly (#34).

### Changed

- Unclear error message when `roles.httpd` config is not applied yet (#33).

## 0.3.0 - 2024-12-27

This release adds TLS support with `listen` configuration parameter.

### Added

- Support TLS for `listen` parameter (#26).

### Fixed

- Update Tarantool dependency to `>=3.0.2` (#25).

## 0.2.0 - 2024-10-02

The release introduces the integration with `httpd` role and latency observation for http
endpoint. Now it is possible to [reuse server's address from `httpd` role config
for `metrics-export-role` configuration](README.md#integration-with-httpd-role).

### Added

- Introduce latency observation for http endpoint (#17).
- Support `roles.httpd` integration (#15).

## 0.1.0 - 2024-06-11

The release introduces the `metrics-export-role` module: export metrics
from `Tarantool` 3. The release contains role for `Tarantool` 3 with
documentation.

### Added

- The role implementation (#6).
- A documentation for the role to README.md (#5).
