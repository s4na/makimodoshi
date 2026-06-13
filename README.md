# makimodoshi

[![CI](https://github.com/s4na/makimodoshi/actions/workflows/ci.yml/badge.svg)](https://github.com/s4na/makimodoshi/actions/workflows/ci.yml)

**makimodoshi** is a Rails gem that helps roll back orphaned database migrations that no longer exist in the current branch. It solves the common pain point of branch switching leaving behind applied migrations after their files disappear.

## The Problem

When working on a Rails app with multiple branches:

1. You run `db:migrate` on `feature-A`, applying new migrations
2. You switch to `main` — the migration **files** disappear, but the **DB changes remain**
3. `rails s` starts with an inconsistent state: `schema.rb` says one thing, the DB says another
4. You get mysterious errors, or worse, you don't notice and keep developing on a broken foundation

The usual fix is `db:rollback` (hoping the files still exist) or `db:reset` (losing all seed data). Both are tedious, error-prone, and easy to forget.

## The Solution

makimodoshi stores migration source code when migrations are applied, then uses that stored source to roll back orphan migrations when needed — even if the original migration files have been deleted by a branch switch.

## Installation

Add to your `Gemfile` in the **development group**:

```ruby
group :development do
  gem "makimodoshi", git: "https://github.com/s4na/makimodoshi.git"
end
```

Then run:

```
$ bundle install
```

That's it. No generators, no initializers, no configuration needed.

> **Note**: This gem is not published on RubyGems. GitHub リポジトリから直接インストールしてください。

## How It Works

### 1. Automatic Storage (`db:migrate`)

Every time you run `db:migrate`, makimodoshi saves a copy of each migration's source code to a hidden database table (`_makimodoshi_migrations`). This table is:

- Automatically excluded from `schema.rb` dumps (won't pollute your schema)
- Created on first use (no setup migration required)

### 2. Automatic Rollback (`rails s`)

When `rails s` starts, makimodoshi compares the `schema.rb` version with the database's `schema_migrations` table. If the DB is ahead, the excess migration files are missing, and `db/schema.rb` has a git diff, it automatically rolls back the orphan migrations using the stored source code.

```
$ rails s
[makimodoshi] DB is ahead of schema.rb by 2 migration(s): 20240301000000, 20240201000000
[makimodoshi] Auto-rolling back...
[makimodoshi] Rolling back 20240301000000 (20240301000000_add_tags_to_posts.rb)...
[makimodoshi] Rolled back 20240301000000.
[makimodoshi] Rolling back 20240201000000 (20240201000000_create_comments.rb)...
[makimodoshi] Rolled back 20240201000000.
[makimodoshi] Auto-rollback complete.
=> Booting Puma
...
```

If orphan migrations exist but `db/schema.rb` has no git diff, makimodoshi skips automatic rollback. In that case, run `rails makimodoshi:rollback` when you intentionally want to roll back the most recent orphan migration.

### 3. Safety

- **Development only**: All DB operations are restricted to `Rails.env.development?`. In any other environment, the gem does nothing and prints a warning.
- **No schema pollution**: The hidden table is excluded from `schema.rb` via `SchemaDumper.ignore_tables`.
- **No-op when in sync**: If the DB matches `schema.rb`, startup cost is minimal (one file read + one DB query).
- **Git diff guard**: Automatic rollback only runs when `db/schema.rb` has a git diff, avoiding surprise rollback immediately after a branch checkout.

## Rake Tasks

### Check stored migrations

```
$ rails makimodoshi:status
[makimodoshi] Stored migrations:
  Version          Filename                                           Migrated At
  ---------------- -------------------------------------------------- --------------------
  20240301000000   20240301000000_add_tags_to_posts.rb                2024-03-01 12:00:00
  20240201000000   20240201000000_create_comments.rb                  2024-02-01 12:00:00
```

### Rollback one migration

```
$ rails makimodoshi:rollback
```

Roll back a specific version:

```
$ rails makimodoshi:rollback VERSION=20240201000000
```

### Rollback all excess migrations

```
$ rails makimodoshi:rollback_all
```

This task uses the same `db/schema.rb` git-diff guard as automatic rollback. If orphan migrations exist but `db/schema.rb` has no git diff, use `rails makimodoshi:rollback` to roll them back intentionally, one migration at a time.

## Typical Workflow

```
# On feature-A branch
$ rails db:migrate        # Migrations are applied and stored by makimodoshi

$ git checkout main       # Migration files disappear, DB still has the changes

$ rails makimodoshi:rollback
                          # Explicitly roll back the most recent orphan migration when schema.rb has no git diff
```

## Requirements

- Ruby >= 3.0
- Rails >= 6.1
- `schema.rb` based projects (`structure.sql` is not supported)

## Limitations

- **`structure.sql` is not supported.** Only projects using `schema.rb` are supported.
- **Pre-installation migrations are not covered.** Migrations applied before installing makimodoshi have no stored source code. If rollback is attempted, it will be skipped with a warning.
- **Development only.** This gem is intentionally restricted to the development environment. It will never modify your production database.

## Development

```
$ git clone https://github.com/s4na/makimodoshi.git
$ cd makimodoshi
$ bundle install
$ bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/s4na/makimodoshi.

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
