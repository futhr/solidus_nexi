# Releasing `solidus_nexi`

This runbook separates verification from actions that change GitHub or RubyGems. Never create or push a release tag, GitHub release, or gem without explicit release approval.

The top-level `rake release` task is disabled because Bundler's default task combines tagging, pushing, and publication.

## First-release prerequisites

- Confirm that the `solidus_nexi` name is available and configure its pending trusted publisher or establish ownership on RubyGems.
- Enable MFA for the RubyGems account. Keep `rubygems_mfa_required` and the RubyGems-only push host in the gemspec.
- Confirm the repository metadata, security contact, and license.
- Complete the merchant TEST lifecycle in [Testing](testing.md), including hosted card entry, webhooks, capture, cancellation, refund, failure cards, and repeated reconciliation.
- Verify the Codecov project and the complete GitHub Actions matrix.

Do not release while any item is unresolved.

## Prepare a release commit

Start from an up-to-date branch based on `main` with no unrelated changes.

1. Choose the version deliberately and update `lib/solidus_nexi/version.rb`.
2. Rename `Unreleased` in `CHANGELOG.md` to the exact version and release date. Open a new empty `Unreleased` section above it.
3. Update version-specific installation examples if needed.
4. Commit those changes as one release-preparation commit and open a pull request.
5. Merge only after review, CI, and merchant release evidence are green.

Run the local checks from the reviewed release commit:

```sh
bin/setup
bin/check-env
bin/rake extension:test_app
CI=1 bin/rake
NEXI_TEST_ENVIRONMENT=1 bundle exec rspec spec/provider
bundle exec rubocop
bundle exec bundler-audit check --update --ignore CVE-2026-47736 CVE-2026-47737
(cd spec/dummy && bin/rails zeitwerk:check)
gem build solidus_nexi.gemspec
ruby dev/verify_package.rb solidus_nexi-*.gem
```

The ignored Puma advisories apply only to the development server pulled in by `solidus_dev_support`; Puma is not a runtime dependency. Remove the exceptions when that helper accepts a patched Puma version.

Inspect the gem metadata and calculate the checksum without changing external state:

```sh
NEXI_RELEASE_VERSION=$(bundle exec ruby -Ilib -rsolidus_nexi/version -e 'print SolidusNexi::VERSION')
NEXI_GEM_ARTIFACT="solidus_nexi-${NEXI_RELEASE_VERSION}.gem"
gem specification "$NEXI_GEM_ARTIFACT" --yaml
shasum -a 256 "$NEXI_GEM_ARTIFACT"
```

Keep that exact artifact. Do not rebuild between inspection and publication.

## Tag and publish

Stop here until a maintainer explicitly approves the release version, commit, artifact checksum, and publication.

After approval:

1. Confirm `main` is clean, synchronized with `origin/main`, and points at the reviewed release commit.
2. Create one annotated `vVERSION` tag at that commit.
3. Inspect the tag target and message locally.
4. Push only the approved tag. Tag CI validates that its name matches the packaged version; it does not publish anything.
5. Publish the already inspected gem with an MFA-protected session, or use RubyGems Trusted Publishing after its GitHub environment has been configured with required reviewers.
6. Verify the RubyGems checksum, metadata links, owners, MFA indicator, and installation in a clean Solidus application.
7. Create matching GitHub release notes from `CHANGELOG.md`.

Never store a RubyGems API key in the repository. Prefer RubyGems Trusted Publishing with a protected `release` environment for later releases because it uses a short-lived, gem-scoped credential.

## After publication

- Install the published version in a clean Solidus app.
- Run the generator, migrations, eager-load check, and a checkout smoke test.
- Confirm the RubyGems, GitHub, and changelog versions agree.
- Keep the legacy `v2.1.0` archive tag unchanged.
