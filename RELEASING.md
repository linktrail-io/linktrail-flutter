# Releasing

`linktrail_flutter` is published to [pub.dev](https://pub.dev/packages/linktrail_flutter) by
`.github/workflows/publish.yml` when a `vX.Y.Z` tag is pushed. It authenticates with GitHub OIDC
([automated publishing](https://dart.dev/tools/pub/automated-publishing)), so no secrets are stored.

## One-time pub.dev setup

1. Sign in to pub.dev as an uploader (or verified-publisher admin) of `linktrail_flutter`.
   Automated publishing can only be enabled after the first version exists on pub.dev; publish that
   one manually with `flutter pub publish` if needed.
2. Open https://pub.dev/packages/linktrail_flutter/admin.
3. Under **Automated publishing**, tick **Enable publishing from GitHub Actions**.
4. Repository: `linktrail-io/linktrail-flutter`.
5. Tag pattern: `v{{version}}`.
6. Optional: tick **Require GitHub Actions environment**, name it (e.g. `pub.dev`), create that
   environment in the GitHub repo settings (with required reviewers if you like), and add
   `environment: pub.dev` to the `publish` job.
7. Save.

## Release steps

1. On a branch, bump `version:` in `pubspec.yaml` and add a `## X.Y.Z` entry at the top of
   `CHANGELOG.md`. Open a PR to `main` and merge it.
2. Tag the merge commit and push the tag:
   ```sh
   git checkout main && git pull
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
3. Watch the **Publish to pub.dev** workflow. It fails without publishing if the tag doesn't match
   `pubspec.yaml`, CHANGELOG has no entry, or analyze/test/dry-run fail.
