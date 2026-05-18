.PHONY: test lint check setup

test:
	bundle exec rspec

lint:
	bundle exec rubocop

check: test lint

setup:
	bundle install
