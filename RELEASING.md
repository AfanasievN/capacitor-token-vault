# Releasing

Releases are intentionally manual until the npm package name and trusted-publisher configuration are owned by the maintainer. This avoids a release workflow that looks complete but fails at publication time.

## One-time setup

1. Claim `capacitor-token-vault` on npm.
2. Configure npm trusted publishing for this GitHub repository and the release workflow that will publish it.
3. Require the CI, CodeQL, and dependency-review checks on `main`.
4. Add the npm package URL as the GitHub repository homepage after the first publication.

## Release checklist

1. Update `CHANGELOG.md` and remove any statements that are not verified.
2. Set the package version with `npm version <patch|minor|major>`.
3. Run `npm ci`, `npm run verify`, and `npm pack --dry-run`.
4. Build Android and iOS using the commands in `CONTRIBUTING.md`.
5. Push the version commit and tag, wait for all required checks, then publish from a clean checkout.
6. Create a GitHub release from the same tag and paste the matching changelog section.

Do not publish with `--ignore-scripts`: package verification is part of the release gate.
