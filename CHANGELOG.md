# Changelog

All notable changes to Lumen will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) starting from `v0.1.0`.

## [Unreleased]

### Added
- Open-source prep: LICENSE (MIT), CONTRIBUTING, CODE_OF_CONDUCT, SECURITY.
- Bilingual README (EN / RU).
- CI workflow building and testing on iOS Simulator.
- Issue and PR templates.

### Changed
- Code comments translated to English across `Sources/`, `Tests/`, `Examples/`.
- `DEVELOPMENT_TEAM` removed from `project.yml` — users select their own team in Xcode.
- Built-in lab URLs default to `127.0.0.1` instead of a hardcoded LAN IP.

### Removed
- Personal work-log directory `sessions/` (now gitignored).

---

This is the initial open-source state. Prior development happened in a private repo; the entries above describe what was needed to make the codebase publishable, not the engineering work itself. Phase-by-phase engineering history is summarized in [docs/ROADMAP.md](docs/ROADMAP.md).
