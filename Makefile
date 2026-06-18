.PHONY: dev setup deps server migrate reset test deploy deploy-full hooks

# Start the Phoenix dev server (installs deps + sets up DB on first run)
dev: deps
	mix phx.server

# One-time project setup: deps, database, assets
setup:
	mix setup

# Install git hooks (run once after cloning)
hooks:
	git config core.hooksPath .githooks
	@echo "Git hooks installed — version will auto-bump on commits to main."

# Fetch Elixir dependencies
deps:
	mix deps.get

# Alias for the dev server without the deps check
server:
	mix phx.server

# Create/run database migrations
migrate:
	mix ecto.migrate

# Drop and recreate the database from scratch
reset:
	mix ecto.reset

# Run the test suite
test:
	mix test

# VPS deploy: update the working tree to latest main, then run the deploy script
deploy:
	git checkout main
	git pull --ff-only origin main
	./deploy.sh

# VPS full deploy: update latest main, then force a full release extract/restart
deploy-full:
	git checkout main
	git pull --ff-only origin main
	./deploy.sh --full
