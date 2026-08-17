# Contributing

Work on a branch from `main` and keep commits focused. Do not commit credentials, `.env`, generated gems, the dummy app, or coverage output.

Before opening a pull request, run:

```sh
bin/setup
bin/rake extension:test_app
CI=1 bin/rake
bin/zeitwerk-check
bundle exec rubocop
bundle exec bundler-audit check --update --ignore CVE-2026-47736 CVE-2026-47737
gem build solidus_nexi.gemspec
ruby dev/verify_package.rb solidus_nexi-*.gem
```

Add regression coverage for behavior changes. Keep migrations portable across SQLite, PostgreSQL, and MySQL, and update `CHANGELOG.md` for user-visible changes.

Tags and RubyGems publication are maintainer release operations. Never create, move, push, or delete a release tag without explicit release approval. The automatic `rake release` task is intentionally disabled because it combines tagging, pushing, and publication.
