# Contributing

Work on a branch from `main` and keep commits focused. Do not commit credentials, `.env`, generated gems, the dummy app, or coverage output.

Before opening a pull request, run:

```sh
bin/setup
bin/rake extension:test_app
CI=1 bin/rake
bin/zeitwerk-check
bundle exec rubocop
bundle exec bundler-audit check --update
gem build solidus_nexi.gemspec
ruby dev/verify_package.rb solidus_nexi-*.gem
bundle exec ruby dev/smoke_package.rb solidus_nexi-*.gem
```

Add regression coverage for behavior changes. Keep migrations portable across SQLite, PostgreSQL, and MySQL, and update `CHANGELOG.md` for user-visible changes.

Tags and RubyGems publication are maintainer release operations. Never create, move, push, or delete a release tag without explicit release approval. The automatic `rake release` task is intentionally disabled because it combines tagging, pushing, and publication.

## PostgreSQL 18.6 and local validation

The PostgreSQL baseline is 18.6 with `pg` 1.6.3 or later in the 1.6 series.
Build the source gem against PostgreSQL 18.6/libpq 18.6. On Debian 12 or Ubuntu
24.04, `bin/setup-postgresql-client` installs the pinned PGDG client. On macOS,
use `brew install postgresql@18` and set `BUNDLE_BUILD__PG` to
`--with-pg-config=$(brew --prefix postgresql@18)/bin/pg_config`.

Set `DB=postgresql`, `DB_HOST`, `PGPORT`, `DB_USERNAME`, and `DB_PASSWORD`
before `bundle install` and regenerating the dummy application. Run the full
RSpec suite, eager-loading check, style, audit, and package checks locally.
Use an isolated test database; the dummy generator creates and migrates it.
Verify `PG.library_version` and the server's `server_version_num` are `180006`.

The automatic workflow tests pull requests and pushes to `main` in one
PostgreSQL 18.6 lane with one coverage run per event. Additional Ruby/Rails and
database profiles are explicit manual `full_matrix` checks. Run them locally
for affected compatibility changes; do not dispatch Actions to iterate on
failures. There are no scheduled test runs.
