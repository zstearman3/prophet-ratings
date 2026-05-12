DC := docker compose

.PHONY: help build up down restart logs logs-web logs-worker ps shell console migrate prepare setup-data test bundle-install yarn-install reset-db

help:
	@echo "Available commands:"
	@echo "  make build          Build Docker images"
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
	@echo "  make prepare        Run Rails db:prepare"
	@echo "  make setup-data     Run the project data setup script"
	@echo "  make test           Run the RSpec test suite"
	@echo "  make bundle-install Run bundle install in the web container"
	@echo "  make yarn-install   Run yarn install in the web container"
	@echo "  make reset-db       Stop containers, remove DB volume, restart, and set up DB"

build:
	$(DC) build

up:
	$(DC) up -d

down:
	$(DC) down

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
	$(DC) exec web bin/rails db:prepare

setup-data:
	$(DC) exec web bin/setup_data

test:
	$(DC) run --rm web bundle exec rspec

bundle-install:
	$(DC) exec web bundle install

yarn-install:
	$(DC) exec web yarn install

reset-db:
	$(DC) down -v
	$(DC) up -d
	$(DC) exec web bin/rails db:setup
