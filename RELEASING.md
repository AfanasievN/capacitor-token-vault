# Releasing

GitHub releases publish to npm through OpenID Connect (OIDC). The workflow receives a short-lived credential from npm, so the repository does not store an `NPM_TOKEN` secret.

## One-time setup

1. Sign in to npm with two-factor authentication and publish `v0.1.0` once from a clean checkout to claim `capacitor-token-vault`:

   ```sh
   git switch --detach v0.1.0
   npm ci
   npm run verify
   npm publish --access public
   ```

2. In the package settings on npm, add a GitHub Actions trusted publisher with these exact values:

   - Organization or user: `AfanasievN`
   - Repository: `capacitor-token-vault`
   - Workflow filename: `publish.yml`
   - Environment: leave empty
   - Allowed action: `npm publish`

3. Under **Publishing access**, select **Require two-factor authentication and disallow tokens**.
4. Require the CI, CodeQL, and dependency-review checks on `main`.
5. Add the npm package URL as the GitHub repository homepage after the first publication.

## Release checklist

1. Update `CHANGELOG.md` and remove any statements that are not verified.
2. Set the package version with `npm version <patch|minor|major>`.
3. Run `npm ci`, `npm run verify`, and `npm pack --dry-run`.
4. Build Android and iOS using the commands in `CONTRIBUTING.md`.
5. Push the version commit and tag, then wait for all required checks.
6. Create a GitHub release from the same tag and paste the matching changelog section. Publishing the release triggers `.github/workflows/publish.yml`, which verifies the tag and package before publishing to npm.
7. Confirm the workflow succeeded and verify the version and provenance on npm.

The workflow can be run manually for an existing GitHub release by supplying its tag. It refuses tags that do not match the version in `package.json`.

Do not publish with `--ignore-scripts`: package verification is part of the release gate.
