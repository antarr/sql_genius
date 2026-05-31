# Changelog

## 0.9.0

### Added
- **PostgreSQL support across the dashboard.** Analyses (table sizes, query stats, unused indexes, server overview, duplicate indexes, query history) and the query detail page now run against PostgreSQL in addition to MySQL/MariaDB. Dialect is detected automatically from the `ActiveRecord::Base.connection`.
- `SqlGenius::Core::QueryBuilders` — dialect-aware SQL generation layer with two builders (`Mysql` covering MySQL/MariaDB, `Postgresql`). Analyses delegate SQL generation through it.
- `SqlGenius::Core::Analysis::QueryHistory` — single-digest stats lookup used by the query detail page; reads `pg_stat_statements` on PG, `performance_schema.events_statements_summary_by_digest` on MySQL.
- `SqlGenius::Core::Analysis::DuplicateIndexes` now includes a `drop_sql` field per result (`ALTER TABLE ... DROP INDEX` on MySQL, `DROP INDEX IF EXISTS "..."` on PG). The dashboard JS uses this instead of assembling MySQL syntax client-side.
- `SqlGenius::Core::UnsupportedDialect` error class. `VariableReviewer`, `ConnectionAdvisor`, and `InnodbInterpreter` raise it on PG so the UI surfaces a clear "MySQL/MariaDB-only" message instead of a raw `PG::SyntaxError`. Controller-side `root_cause` and `anomaly_detection` short-circuit on PG with the same kind of error.
- `Core::ServerInfo` recognises `:postgresql` as a vendor; exposes `#postgresql?` and `#dialect`.
- `Core::QueryRunner` issues `SET statement_timeout = ms` (and resets to 0 in an `ensure` block) on PostgreSQL; recognises `canceling statement due to statement timeout` as a timeout error.
- `Core::SqlValidator` blocks PG system schemas (`pg_catalog`, `pg_toast`, `pg_temp`) and parses double-quoted identifiers.

### Changed
- The gem and public brand now use `sql_genius` / `SqlGenius`. The default mount path, install generator, initializer path, require paths, GitHub links, and RubyGems publishing workflow now use the new name.
- **`sql_genius-core` has been merged back into the main `sql_genius` gem.** The split was originally added to support a planned desktop app; with that path discontinued, the two gems become one. Host apps no longer need `gem "sql_genius-core"` in their Gemfile — it's gone, and the runtime dependency in `sql_genius.gemspec` is gone too. The `SqlGenius::Core::*` namespace is preserved, so all existing `require` paths and constant lookups continue to work unchanged.
- `ActiveRecordAdapter#server_version` is memoized — dialect detection runs `SELECT VERSION()` at most once per adapter instance.
- Tab header text in Tables / Query Stats / Unused Indexes no longer mentions `performance_schema` / `information_schema` by name.

### Removed
- The `sql_genius-desktop` gem stub. Desktop sidecar / macOS DMG packaging scripts (`packaging/macos/`) are removed; they only assembled the now-deleted gem.
- `SqlGenius::Core::VERSION` constant. Use `SqlGenius::VERSION`.

### Unused Indexes: PgHero-style context
- `GET /sql_genius/unused_indexes` now returns `{ indexes: [...], stats_reset_at, min_scans }` instead of a bare array. The Unused Indexes tab shows "Stats last reset N ago · threshold: scans ≤ M" above the table so an empty/fresh stats source doesn't read as "everything is unused."
- New `config.min_unused_index_scans` (default 0 — PgHero parity). Raise it (e.g. 50) to ignore indexes that are technically used but rarely enough to consider dropping.
- The PG query now sorts results by index byte size DESC (largest first — biggest wins). Each result hash carries a `size_bytes` field; the table shows a Size column. `pg_relation_size` is the source.
- Removed the `c.reltuples > 0` filter so indexes on empty tables show up too (matches PgHero — empty tables with indexes are still actionable noise).

### Notes
- PostgreSQL query stats require the `pg_stat_statements` extension to be installed and enabled (`shared_preload_libraries`).
- Slow query log capture remains MySQL-only.

## 0.8.1

### Fixed
- **Older MySQL compatibility** — the `DIGEST` column in `performance_schema.events_statements_summary_by_digest` is not present on all MySQL/MariaDB versions. `QueryStats` now checks for column existence before including it in the SELECT. Query links in the Query Stats tab gracefully degrade to plain text when the digest is unavailable.

## 0.8.0

### Added
- **6 new AI analysis features:**
  - **Variable Config Reviewer** — reviews my.cnf settings against observed workload
  - **Connection Pressure Advisor** — diagnoses connection pool health
  - **Workload Digest** — executive summary of the entire query workload
  - **InnoDB Health Interpreter** — plain English translation of `SHOW ENGINE INNODB STATUS`
  - **Index Consolidation Planner** — holistic drop/merge/add index plan across tables
  - **Slow Query Pattern Grouper** — groups slow queries by shared root cause
- AI buttons added to Server tab, Query Stats tab, and Indexes tabs
- `sql_genius` now declares runtime dependency on `sql_genius-core ~> 0.8.0`

## 0.7.2

### Added
- **Anthropic Messages API support** — `x-api-key` auth style with `anthropic-version` header, top-level `system` parameter, `content[0].text` response parsing.
- **Configurable `max_tokens`** — new field on `Core::Ai::Config` (default 4096), sent to both OpenAI and Anthropic APIs.
- **Copy response button** on all AI result sections (schema review, migration risk, optimization, describe query, rewrite, index advisor, root cause, anomaly detection).
- **Dark mode contrast fixes** for AI result sections — proper CSS classes with dark-mode variants replace hardcoded light-mode inline styles.
- **`capability?(:standalone_header)`** guard hides the dashboard header when rendered inside a layout that already provides one.

## 0.7.1

Lockstep version bump with `sql_genius-core 0.7.1` which fixes missing ERB templates in the gem package.

## 0.7.0

### Added
- **`capability?(name)` helper** in `SharedViewHelpers`. The Rails adapter returns `true` for all capabilities; the desktop sidecar uses it to hide Redis-backed features (slow_queries, anomaly_detection, root_cause) from the shared dashboard templates.
- **Query detail page** at `GET /queries/:digest` with syntax-highlighted SQL, Explain button, aggregate stats cards, and three inline SVG time-series charts (Total Time, Average Time, Calls).
- **`Core::Analysis::StatsHistory`** — thread-safe in-memory ring buffer for per-digest query stats snapshots (24hr retention at 60s intervals).
- **`Core::Analysis::StatsCollector`** — background thread that samples `performance_schema.events_statements_summary_by_digest` every 60s, computes deltas, and records to StatsHistory.
- **`DIGEST` hash** added to `Core::Analysis::QueryStats` return value for stable URL keys.
- **Stats collection config option** (`stats_collection`, default `true`) — controls whether the background collector starts on boot.
- **Query Stats tab linkification** — SQL cells in the Query Stats table are now clickable links to the query detail page.
- `sql_genius` now declares runtime dependency on `sql_genius-core ~> 0.7.0`.

## 0.6.0

### Changed
- **Dropped Rails 5.2 support.** The gemspec floor is now Rails 6.0 (`activerecord`/`railties` constraint is `">= 6.0", "< 9"`). Rails 5.2 has been end-of-life since June 2022 and its incompatibilities with modern Rack (`ActionDispatch::Static#initialize` arity mismatch, `MiddlewareStack#operations` removal) started surfacing as CI failures once Phase 2a's integration specs booted Rails in test. Pin `sql_genius 0.5.0` (`gem "sql_genius", "~> 0.5.0"`) if you can't upgrade Rails yet.
- `sql_genius` now declares runtime dependency on `sql_genius-core ~> 0.6.0` (was `~> 0.5.0`).

### Fixed
- **CI matrix: Ruby 3.x + Rails 5.2/6.0/6.1 compatibility.** `spec/rails_helper.rb` and `spec/dummy/config/application.rb` now explicitly `require "logger"` before loading Rails. Works around a `Logger::Severity` reference inside `ActiveSupport::LoggerThreadSafeLevel` that fails on Ruby 3.x + older Rails because Logger is no longer autoloaded in modern Ruby. Only affects the test suite; no runtime impact on host apps.

### Internal
- **`rails_connection` consolidated into `BaseController`.** Nine inline `SqlGenius::Core::Connection::ActiveRecordAdapter.new(ActiveRecord::Base.connection)` call sites in the three controller concerns, plus two separate private helper definitions in `QueriesController` and `AiFeatures`, collapse to one private method on `BaseController`. Shared across all concerns via Ruby's standard method lookup.
- **`ai_domain_context` helper inlined and deleted.** Its two remaining callers (`anomaly_detection` and `root_cause`) now compute a local `domain_ctx` string before building their message array.
- **`fake_result(columns:, rows:, to_a:)` test helper extracted** into `spec/support/fake_connection.rb` alongside `fake_column`. Four duplicated `instance_double("ActiveRecord::Result", columns:, rows:, to_a:)` call sites in request specs refactored.
- **`Core::Analysis::Columns` spec** covers the `default: false` branch (6th column outside `default_columns`).
- **`actions/checkout@v4` bumped to `@v5`** in both `.github/workflows/ci.yml` and `.github/workflows/publish.yml`. Prepares for GitHub's June 2026 Node 20 deprecation.
- **Gemspec `source_code_uri` duplicate dropped** from both gemspecs (was equal to `homepage_uri` and triggered a RubyGems build warning on every release).

### Documentation
- README Compatibility table no longer lists Rails 5.2. The note explaining the drop and pinning instructions stays in place.

## 0.5.0

### Changed
- **ERB templates moved into `sql_genius-core`.** All 11 view files (`dashboard.html.erb` and 10 partials) have been extracted from `app/views/sql_genius/queries/` into `gems/sql_genius-core/lib/sql_genius/core/views/sql_genius/queries/`. The index template is renamed to `dashboard.html.erb`. The engine registers `SqlGenius::Core.views_path` before `:add_view_paths` so Rails finds templates in both view roots. Non-Rails adapters (Phase 2b `sql_genius-desktop` sidecar) can register this same path with their own view loader and implement `path_for`/`render_partial` to reuse the templates.
- **`QueriesController#index`** now sets `@framework_version_major` and `@framework_version_minor` instance variables (replacing direct `Rails::VERSION` references in the template) and explicitly renders `"sql_genius/queries/dashboard"`.
- **`SharedViewHelpers`** — new concern providing `path_for(name)` and `render_partial(name)` as the 2-method contract the shared templates depend on. `render_partial` delegates to `view_context.render(partial: "sql_genius/queries/#{name}")`.
- Extracted 5 AI prompt builders from the `AiFeatures` concern into `SqlGenius::Core::Ai::{DescribeQuery, SchemaReview, RewriteQuery, IndexAdvisor, MigrationRisk}` plus a shared `Core::Ai::SchemaContextBuilder` helper. `anomaly_detection` and `root_cause` remain in the Rails concern because they depend on the Redis-backed `SlowQueryMonitor`.
- Extracted `QueriesController#columns` logic into `SqlGenius::Core::Analysis::Columns` with a tagged-result struct. Retires the `masked_column?` helper added in the 0.4.1 hotfix.
- `SqlGenius::Core::Ai::Config` gains a `domain_context:` field. The Rails adapter defaults it to a Rails-specific string; `sql_genius-desktop` will default to empty.
- `sql_genius` now declares runtime dependency on `sql_genius-core ~> 0.5.0` (was `~> 0.4.0`).

### Added
- Integration test suite at `spec/dummy/` + `spec/rails_helper.rb` + `spec/requests/`. Boots a minimal Rails engine dummy app and dispatches real HTTP requests against the mounted engine via `Rack::Test`. Dedicated regression specs at `spec/regressions/` pin the two Phase 1b latent bugs (`Core::Connection::ActiveRecordAdapter` boot-order and `QueriesController#masked_column?` helper deletion) so they can never silently return.
- `CLAUDE.md` updated: the "no Rails boot in tests" rule is relaxed to a two-tier model (unit specs stub AR, integration specs boot Rails via `spec/dummy/`).

### Internal
- `SqlGenius::Core.views_path` — new public module method returning the absolute path to the shared ERB template directory.

## 0.4.1

### Fixed
- **`GET /columns` endpoint raised `NoMethodError: undefined method 'masked_column?'` at runtime** — a second Phase 1b regression (0.4.0 also shipped the `ActiveRecordAdapter` boot-order bug). When `SqlValidator::masked_column?` was promoted to a 2-arg class method during Phase 1b, the one remaining caller in `QueriesController#columns` was not updated. Clicking a table in the Query Explorer dropdown on 0.4.0 hits this route and triggers a 500. Fixed by reintroducing a private `masked_column?(name)` helper on `QueriesController` that delegates to `SqlGenius::Core::SqlValidator.masked_column?(name, sql_genius_config.masked_column_patterns)`. The call site on line 30 is untouched. Regression guard is deferred to Phase 2a's planned `spec/dummy/` Rails dummy app — the project's "no Rails boot in tests" policy blocks writing a controller-level unit spec for this without novel scaffolding. Empirically verified in-process: `masked_column?("password_hash") == true`, `masked_column?("email") == false`, `masked_column?("api_token") == true`.

## 0.4.0

### Fixed
- **Boot-order bug: `SqlGenius::Core::Connection::ActiveRecordAdapter` was not required by `lib/sql_genius.rb`** — shipped in Phase 1a but never wired into the production require chain. Invisible to CI because the adapter's spec file explicitly required it, and invisible in development because pre-Phase-1b concerns didn't reference it. Phase 1b's extracted delegators instantiate it in every action, so the missing require would have surfaced as `uninitialized constant` on every tab (tables, query stats, unused indexes, duplicate indexes, server overview, execute, explain, AI suggest, AI optimize) in any host app that installed 0.4.0 without the fix. `lib/sql_genius.rb` now explicitly requires the adapter after loading `sql_genius/core`, and `spec/spec_helper.rb` has a regression guard that aborts the spec suite at boot if the constant is not reachable via a plain `require "sql_genius"`.

### Changed
- **Internal refactor: extracted Rails-free core library into a new `sql_genius-core` gem.** The validator, AI services, value objects, database analyses, query runner, and query explainer now live in `sql_genius-core`; the `sql_genius` Rails engine delegates through a new `Core::Connection::ActiveRecordAdapter`. Public API, routes, config DSL, and JSON response shapes are unchanged — host apps see no difference after `bundle update`. See [the design spec](docs/superpowers/specs/2026-04-10-desktop-app-design.md) for the motivation: the new core gem is the foundation for a forthcoming `sql_genius-desktop` standalone app.
- `sql_genius` now declares a runtime dependency on `sql_genius-core ~> 0.4.0`. The two gems release in lockstep under matching version numbers (0.4.0 is the first paired release); the dependency resolves transitively, so host apps do not need to add `sql_genius-core` to their Gemfile.
- `SqlGenius::SqlValidator` moved to `SqlGenius::Core::SqlValidator`.
- `SqlGenius::AiClient`, `SqlGenius::AiSuggestionService`, `SqlGenius::AiOptimizationService` moved to `SqlGenius::Core::Ai::{Client, Suggestion, Optimization}` and now take an explicit `Core::Ai::Config` instead of reading `SqlGenius.configuration` at construction time.
- The 5 database analyses (`table_sizes`, `duplicate_indexes`, `query_stats`, `unused_indexes`, `server_overview`) moved from the `DatabaseAnalysis` controller concern into `SqlGenius::Core::Analysis::*` classes, each taking a `Core::Connection`. The concern shrunk from ~295 lines to 47 lines of thin delegating wrappers.
- `SqlGenius::Core::QueryRunner` now owns SQL validation, row-limit application, timeout-hint wrapping (MySQL / MariaDB flavors), execution, column masking, and timeout detection. The `execute` controller action delegates to it. Audit logging stays in the Rails adapter.
- `SqlGenius::Core::QueryExplainer` now owns the EXPLAIN path with optional validation-skipping for captured slow queries. The `explain` controller action delegates to it.

### Documentation
- Added README troubleshooting section covering `SSL_connect ... EC lib` / `unable to decode issuer public key` errors that hit Ruby 2.7 + OpenSSL 1.1.x users talking to Google Trust Services-backed hosts like Ollama Cloud. Recommends local Ollama (`http://localhost:11434`) as the fastest unblock, `SSL_CERT_FILE` pointing at a fresher CA bundle as an intermediate fix, and upgrading to Ruby 3.2+ as the durable fix.
- Added `docs/superpowers/specs/2026-04-10-desktop-app-design.md` — the full design spec for the eventual `sql_genius-desktop` standalone app.

## 0.3.2

### Fixed
- **Query Stats tab stuck on loading spinner** -- commented-out HTML controls in `_tab_query_stats.html.erb` left corresponding JavaScript (`el('qstats-sort').value` and two `addEventListener` calls) throwing `TypeError` on null elements, killing `loadQueryStats` before it could issue its fetch. The commented-out markup and the dead JavaScript have both been removed; client-side sortable column headers continue to provide sort UX.

## 0.3.1

### Added
- **Sortable columns** -- click any column header to sort ascending/descending on all data tables
- **Automated RubyGems publishing** -- GitHub Actions workflow publishes gem on tag push

### Fixed
- **Query stats noise** -- SQLGenius internal queries (information_schema, performance_schema, SHOW, etc.) are now excluded from the Query Stats tab

## 0.3.0

### Improved
- **SQL syntax highlighting** -- SQL code blocks in tables now feature a dark-themed syntax highlighter with distinct colors for keywords, functions, strings, numbers, operators, identifiers, and placeholders (Catppuccin Mocha palette)
- **Table visual hierarchy** -- redesigned table headers (uppercase, thicker bottom border, rounded top corners), improved row hover states (blue tint), cleaner alternating row colors, removed vertical cell borders
- **Numeric column formatting** -- right-aligned with monospace tabular-nums font for easy scanning; duration values color-coded green/amber/red by severity
- **Overall dashboard polish** -- more generous cell padding, improved inline `code` tag styling, added `mg-badge-success` variant
- **Tab persistence** -- active tab is remembered across page reloads via URL hash

### Fixed
- **Unused indexes SQL error on MySQL 8.0+** -- `reads` and `writes` are reserved words and now use backtick quoting

### Added
- **Dark theme** -- auto-detects system preference, manual toggle via sun/moon button, persisted in localStorage
- **Tables tab** -- renamed from "Table Sizes", now shows engine, collation, auto-increment, last updated, and accurate row counts via `COUNT(*)`
- **Optimize suggestions** -- tables with >10% fragmentation are flagged with an optimize badge

## 0.2.0

- **Dashboard-first redesign** -- new default landing page with server health, top slow queries, top expensive queries, and index alert badges
- **Query Explorer** -- merged Visual Builder and SQL Query into one tab with a mode toggle
- **Suggested migrations** -- duplicate and unused index tabs generate timestamped Rails migrations with copy-to-clipboard
- **Install generator** -- `rails generate sql_genius:install` creates initializer and mounts the engine
- **RuboCop** -- added rubocop-shopify and rubocop-rspec, enforced across the codebase
- **CI matrix** -- added Ruby 3.4, Rails 8.0 and 8.1; excluded incompatible Ruby 3.4 + Rails 6.1/7.0 combos
- **Smarter AI prompts** -- schema review now includes primary keys and Rails-aware context (no foreign key constraint recommendations, recommends indexes on FK columns instead)
- **SSL fix** -- explicit CA certificate file for AI API requests
- Tab reorder: Dashboard, Slow Queries, Query Stats, Server, Table Sizes, Unused Indexes, Duplicate Indexes, Query Explorer, AI Tools
- Dashboard links to Server tab for full details
- Clipboard fallback for non-HTTPS environments
- Gemspec description updated to lead with monitoring features

## 0.1.0

- Initial release
- Visual query builder with column selection, filters, and ordering
- Safe SQL execution (read-only, blocked tables, masked columns, row limits, timeouts)
- EXPLAIN analysis
- AI-powered query suggestions (optional)
- AI-powered query optimization from EXPLAIN output (optional)
- Slow query monitoring via Redis
- Audit logging
- MariaDB support
