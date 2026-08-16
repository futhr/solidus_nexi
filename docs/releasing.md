# Releasing `solidus_nexi`

The gem is intended to be published to RubyGems under the new `solidus_nexi` name. The legacy `spree_dibs` name and its version sequence are not reused.

This is a maintainer runbook. Publishing changes external state, so every step through package inspection is safe to rehearse; the final push and `gem push` require an explicit release decision.

## Before the first release

1. Confirm that `solidus_nexi` is available or controlled by the maintainers on RubyGems.
2. Confirm that the GitHub repository has been renamed to `futhr/solidus-nexi` and that gemspec metadata resolves there.
3. Require MFA on the RubyGems account and keep `rubygems_mfa_required = true` in the gemspec metadata.
4. Complete the real Nexi merchant test lifecycle described in [Operations](operations.md).
5. Decide whether the first publication remains `0.1.0.alpha.1` or advances to another prerelease version.

Do not publish the package while the public repository URL, security contact, license, or provider test evidence is unresolved.

## Prepare the release

Start from a clean `main` branch and update the version and changelog together. The changelog entry must describe user-visible behavior and preserve its logical commit log; it must not be generated from commit subjects without a human edit.

Run the supported checks:

```sh
bin/setup
bin/rake extension:test_app
bin/rake
bundle exec rubocop
(cd spec/dummy && bin/rails zeitwerk:check)
gem build solidus_nexi.gemspec
```

Inspect the built package before publishing:

```sh
NEXI_GEM_ARTIFACT=solidus_nexi-0.1.0.alpha.1.gem
gem specification "$NEXI_GEM_ARTIFACT" name
gem specification "$NEXI_GEM_ARTIFACT" version
gem specification "$NEXI_GEM_ARTIFACT" required_ruby_version
gem specification "$NEXI_GEM_ARTIFACT" metadata
GEM_HOME=tmp/release-gems gem install --local --ignore-dependencies "$NEXI_GEM_ARTIFACT"
GEM_HOME=tmp/release-gems gem contents solidus_nexi
```

The contents command applies after installing the built gem locally. Also inspect the archive itself and confirm that it includes runtime code, migrations, views, `README.md`, `CHANGELOG.md`, `SECURITY.md`, and `docs/`, but excludes fixtures, credentials, the dummy application, coverage, and legacy DIBS code.

## Git operation pattern

Keep release history linear and reviewable:

1. Commit the final version and changelog as one release-preparation change, for example `Prepare solidus_nexi 0.1.0.alpha.1`.
2. Merge only after CI and the provider release gate are green.
3. Create an annotated tag matching the gem version, for example `v0.1.0.alpha.1`.
4. Push the commit and tag, then verify the tag resolves to the reviewed release commit.
5. Publish the exact gem artifact that was inspected; do not rebuild from a different tree.
6. Verify the RubyGems page, checksums, metadata links, and installation in a clean application.

An annotated alpha tag may preserve a reviewed source snapshot before merchant validation is complete. That tag does not authorize RubyGems publication: the provider test gate and every first-release check above must still pass before `gem push`.

Suggested tag command:

```sh
git tag -a v0.1.0.alpha.1 -m "Release solidus_nexi 0.1.0.alpha.1"
```

## Publish

With the inspected artifact and an MFA-capable RubyGems session:

```sh
gem push solidus_nexi-0.1.0.alpha.1.gem
```

Do not automate the first publication until namespace ownership, MFA, provenance, and artifact verification have all been observed manually. Never place a RubyGems API key in the repository or a command transcript.

## After publishing

- Install the published version in a clean Solidus application rather than from the repository.
- Re-run the generator, migrations, eager-load check, and deterministic test suite.
- Confirm that the RubyGems and GitHub release notes match `CHANGELOG.md`.
- Open the next `Unreleased` changelog section before merging additional user-visible work.
- Keep the legacy `v2.1.0` archive tag unchanged.
