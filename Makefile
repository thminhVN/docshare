.PHONY: dev setup deps server migrate reset test

# Start the Phoenix dev server (installs deps + sets up DB on first run)
dev: deps
	mix phx.server

# One-time project setup: deps, database, assets
setup:
	mix setup

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
