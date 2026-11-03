# Security

This document covers the security expectations for Ombre contributors and maintainers.

## Secrets and Sensitive Data

- Never commit `.env` files, signing credentials, private keys, notarization credentials, or any other secret material.
- Do not paste secrets into issues, pull requests, screenshots, or logs shared publicly.
- Treat generated logs and exported artifacts as potentially sensitive until reviewed.

## Signing and Updates

- Debug and Release builds are signed with the development team set in `project.yml`; `./scripts/build.sh` builds a
  Release app and a DMG. Distributing builds to other Macs will need a Developer ID certificate and notarization.
- Automatic updates (Sparkle) are disabled: the app has no update feed or signing key yet. When they are set up, the
  private signing key must never be committed or shared.
- The browser entitlements `com.apple.developer.web-browser` and `com.apple.developer.web-browser.public-key-credential`
  require Apple's approval and are not requested yet: until then, passkeys (WebAuthn) do not work in web pages.

## Safe Working Practices

- Review `git status` and `git diff --cached` before every commit.
- Do not add private keys, provisioning profiles, or notarization credentials to the repository, even temporarily.
- Be careful when sharing crash logs, build logs, and environment output if they may include local paths, account
  identifiers, or signing details.

## Reporting Security Issues

If you discover a security issue or an accidental secret exposure, do not open a public issue. Report it privately
through a [GitHub security advisory](https://github.com/barto95100/ora-browser/security/advisories/new).
