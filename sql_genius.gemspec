# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "sql_genius/version"

Gem::Specification.new do |spec|
  spec.name          = "sql_genius"
  spec.version       = SqlGenius::VERSION
  spec.authors       = ["Antarr Byrd"]
  spec.email         = ["antarr.t.byrd@uth.tmc.edu"]

  spec.summary       = "A SQL performance dashboard and query explorer for Rails."
  spec.description   = "SqlGenius gives Rails apps a mountable performance dashboard for SQL databases. " \
    "Monitor slow queries, analyze query statistics, detect unused and duplicate indexes, " \
    "and explore your database with optional AI-powered optimization."
  spec.homepage      = "https://github.com/antarr/sql_genius"
  spec.license       = "Nonstandard"

  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["changelog_uri"]   = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path("..", __FILE__)) do
    Dir[
      "app/**/*",
      "config/**/*",
      "docs/guides/**/*",
      "docs/screenshots/**/*",
      "lib/**/*",
      "CHANGELOG.md",
      "LICENSE.txt",
      "README.md",
      "Rakefile",
      "sql_genius.gemspec",
    ].uniq
      .select { |f| File.file?(f) }
      .reject { |f| f.match?(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency("activerecord", ">= 6.0", "< 9")
  spec.add_dependency("railties", ">= 6.0", "< 9")
end
