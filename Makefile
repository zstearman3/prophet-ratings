DC := bin/compose

.PHONY: help build up down restart logs logs-web logs-worker ps shell console migrate prepare setup-data test check bundle-install yarn-install reset-db

help:
	@echo "Available commands:"
	@echo "  bin/dev             Start Docker development; Ctrl-C cleans up"
	@echo "  bin/stop            Stop development, preserving data and images"
	@echo "  bin/test [args]     Run isolated Docker specs with automatic cleanup"
	@echo "  bin/check           Run native quality checks and isolated specs"
	@echo "  make build          Build the shared development/test image"
	@echo "  make up             Start the local Docker stack"
	@echo "  make down           Stop the local Docker stack"
	@echo "  make restart        Restart the local Docker stack"
	@echo "  make logs           Follow logs for all services"
	@echo "  make logs-web       Follow Rails web logs"
	@echo "  make logs-worker    Follow GoodJob worker logs"
	@echo "  make ps             Show running Docker Compose services"
	@echo "  make shell          Open a shell in the web container"
	@echo "  make console        Open the Rails console"
	@echo "  make migrate        Run database migrations"
	@echo "  make prepare        Create/migrate the development database without seeds"
	@echo "  make setup-data     Run the project data setup script"
	@echo "  make test           Run isolated Docker specs (ARGS='spec/path_spec.rb')"
	@echo "  make bundle-install Update the native bundle and rebuild the image"
	@echo "  make yarn-install   Run yarn install in the JavaScript container"

build:
	$(DC) build web

up:
	bin/dev --detach

down:
	bin/stop

restart: down up

logs:
	$(DC) logs -f

logs-web:
	$(DC) logs -f web

logs-worker:
	$(DC) logs -f worker

ps:
	$(DC) ps

shell:
	$(DC) exec web bash

console:
	$(DC) exec web bin/rails console

migrate:
	$(DC) exec web bin/rails db:migrate

prepare:
	$(DC) exec web bin/rails db:create db:migrate

setup-data:
	$(DC) exec web bin/setup_data

test:
	bin/test $(ARGS)

check:
	bin/check

bundle-install:
	bundle install
	$(DC) build web

yarn-install:
	$(DC) run --rm --no-deps js yarn install

reset-db:
	@echo "Database deletion is not part of routine setup. See docs/development.md for explicit reset instructions."
	@exit 1
