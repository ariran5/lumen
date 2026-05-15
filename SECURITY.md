# Security policy

## Reporting a vulnerability

If you've found a vulnerability in Lumen — runtime sandbox bypass, origin/permission escalation, network-policy bypass, JS-to-native escape, anything that could let a fast-app reach beyond what its manifest grants — **please don't open a public issue**.

Instead, use **GitHub Security Advisories**:

→ Go to the repo's **Security** tab → **Report a vulnerability**

We'll acknowledge within ~72 hours and work with you on a fix and disclosure timeline.

## Scope

In-scope:

- Sandbox / origin isolation bypasses (cross-origin read of storage, keychain, FS).
- Network-policy bypasses (fetching hosts not in `connect`).
- Permission-prompt bypasses.
- JS-to-native escapes via the JSEngine bridges.
- HTTPS-only gate bypasses outside Developer Mode and local-network exceptions.
- Manifest parsing exploits (integrity, permissions parsing).

Out of scope:

- Anything that requires Developer Mode to be enabled.
- Issues that require a user to type a malicious URL into the address bar (regular WebView caveats).
- Self-XSS in `WKWebView` content (handled by WebKit upstream).
- Denial of service via heavy JS / layout work in a fast-app (rate-limiting is a feature request, not a vuln).

## What to include in a report

- Affected component (file path / module).
- Steps to reproduce, including a minimal manifest + script if applicable.
- Impact — what an attacker can read, write, or do.
- Suggested fix, if you have one.

## Pre-1.0 caveat

Lumen is pre-1.0. The sandbox and permission model are under active design. Some issues may already be tracked publicly in the issue tracker as known limitations — please check before reporting.
