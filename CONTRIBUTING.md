# Contributing to Lumen

Thanks for your interest in Lumen. This document covers how to set up the project locally, how to submit changes, and what to expect from the review process.

> **Status:** pre-1.0. Internal APIs and the fast-app surface can change between commits. If you're planning a larger change, open an issue first so we can discuss direction.

## Setting up

You need:

- macOS with Xcode 15 or newer (iOS SDK 17+).
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`.
- [Bun](https://bun.sh) — `brew install bun`.

Clone, generate the Xcode project, build:

```sh
git clone https://github.com/<owner>/lumen.git
cd lumen
xcodegen generate
open Lumen.xcodeproj
```

For physical-device builds, open the `Lumen` target → Signing & Capabilities, pick your team. The generated `*.xcodeproj` is gitignored, so this stays local.

## Running tests

```sh
xcodebuild test -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

A single suite or test:

```sh
xcodebuild test -scheme Lumen \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:LumenTests/ReactivityTests
```

Please add tests when changing behavior in `LumenRuntime` or `LumenLayout`. Renderer and reactivity bugs are hard to spot without regression coverage — that's why `ReactivityTests` and `ReconcilerTests` exist.

## Running fast-apps

```sh
bun tools/dev-server.ts Examples/HelloApp 8080
```

Then open `http://127.0.0.1:8080` in Lumen (works in the simulator out of the box). For a physical device, use your LAN IP instead.

## Submitting changes

1. **Fork** the repo and create a topic branch off `main`.
2. **Make your change.** Match the surrounding style — no need for additional formatters. Comments in code should be in English.
3. **Add tests** if you're fixing a bug or changing behavior in the renderer/runtime.
4. **Run the test suite locally** before pushing.
5. **Open a PR** against `main`. Fill in the PR template. Link related issues.
6. **Be patient.** This is a small project — review may take a few days.

### Commit messages

- One topic per commit. Avoid mixing refactor + feature + formatting.
- Subject line under ~70 chars. The body can be in any language; the subject prefers English for searchability.
- No automated trailers (Co-Authored-By, Signed-off-by, etc.) unless they're meaningful to the change.

### Scope of changes

We're happy to take:

- Bug fixes with a reproducing test.
- New fast-app APIs (with TS types in `packages/lumen-types` and at least one example in `Examples/`).
- Renderer or layout fixes — please pair with a test in `ReactivityTests` / `ReconcilerTests` / `FlexLayoutTests`.
- Documentation, examples, dev-server improvements.

Please open an issue first if you want to:

- Add a major new subsystem.
- Change the shape of the JS-side runtime API.
- Touch the sandbox / origin / permission model.
- Add third-party dependencies (we currently ship zero — including the layout engine).

## What to expect in review

- We'll look at correctness, simplicity, and whether the change fits the project's direction.
- We may push back on additions that increase API surface without a clear user need.
- For UI changes — please attach a short screen recording or screenshot. UI feel is hard to read from a diff.

## Security issues

Don't open public issues for security vulnerabilities. See [SECURITY.md](SECURITY.md).

## Code of conduct

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
