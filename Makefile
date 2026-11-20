SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

COMPOSE := docker compose --env-file .env -f infra/docker-compose.yml

.PHONY: help env bootstrap up up-full down logs health migrate \
        dev-api dev-ingestor dev-workers dev-web sim \
        codegen codegen-check lint typecheck test clean

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ------------------------------------------------------------------------------
# Setup & Local Infrastructure
# ------------------------------------------------------------------------------
env: ## Idempotently create local env files from templates
	@test -f .env || (cp .env.example .env && echo "Created .env")
	@test -f apps/web/.env.local || (cp apps/web/.env.example apps/web/.env.local && echo "Created apps/web/.env.local")
	@test -f apps/mobile/.env.json || (cp apps/mobile/.env.example.json apps/mobile/.env.json && echo "Created apps/mobile/.env.json")

bootstrap: env ## Install all Python (uv), JS/TS (pnpm), and Dart/Flutter (pub) workspaces
	uv sync --all-packages --all-groups
	pnpm install
	flutter pub get

up: env ## Boot core local infra (TimescaleDB+PostGIS, Redis, EMQX, MinIO)
	$(COMPOSE) up -d

up-full: env ## Boot core infra + NodeODM photogrammetry profile (requires >=16GB RAM)
	$(COMPOSE) --profile photogrammetry up -d

down: ## Stop local infrastructure containers (preserves volumes)
	$(COMPOSE) down

logs: ## Tail infrastructure container logs
	$(COMPOSE) logs -f

health: env ## Verify PostgreSQL extensions, Redis, EMQX, and S3 private buckets
	@set -a && source .env && set +a && \
	echo "==> PostgreSQL + TimescaleDB + PostGIS" && \
	docker exec aqua_postgres psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -c \
		"SELECT extname, extversion FROM pg_extension WHERE extname IN ('timescaledb','postgis','pgcrypto') ORDER BY extname;" && \
	echo "==> Redis" && \
	docker exec aqua_redis redis-cli ping && \
	echo "==> EMQX" && \
	docker exec aqua_emqx /opt/emqx/bin/emqx ctl status && \
	echo "==> S3 Object Store Buckets" && \
	$(COMPOSE) run --rm --no-deps --entrypoint aws s3-init --endpoint-url http://s3:9000 s3 ls
# ------------------------------------------------------------------------------
# Database, Contracts & Runtime Services
# ------------------------------------------------------------------------------
migrate: env ## Run Alembic migrations (TimescaleDB + PostGIS DDL)
	uv run --env-file .env --package aqua-api alembic -c apps/api/alembic.ini upgrade head

codegen: ## Compile packages/contracts schemas into ts-sdk and dart-sdk
	pnpm --filter @aqua/contracts run codegen

codegen-check: ## Fail if generated SDKs drift from packages/contracts
	pnpm --filter @aqua/contracts run codegen:check

dev-api: env ## Run FastAPI HTTP + WebSocket server with reload
	uv run --env-file .env --package aqua-api uvicorn aqua_api.main:app --reload --host 0.0.0.0 --port 8000

dev-ingestor: env ## Run standalone async MQTT ingestion worker
	uv run --env-file .env --package aqua-api python -m aqua_api.ingestion.runner

dev-workers: env ## Run ARQ async compute workers (NodeODM, Kriging/Plume, AI)
	uv run --env-file .env --package aqua-workers arq aqua_workers.worker.WorkerSettings

dev-web: env ## Run Next.js Client Portal + Admin Console
	pnpm --filter @aqua/web dev

sim: env ## Launch virtual drone simulator
	uv run --env-file .env --package drone-simulator python tools/drone-simulator/sim.py

# ------------------------------------------------------------------------------
# Quality Gates (Lint, Typecheck, Test, Clean)
# ------------------------------------------------------------------------------
lint: ## Lint Python (ruff), JS/TS (turbo), and Dart/Flutter (analyze)
	uv run ruff check .
	pnpm lint
	cd packages/dart-sdk && dart analyze
	cd apps/mobile && flutter analyze

typecheck: ## Strict static typechecking across Python (mypy) and TypeScript (turbo)
	uv run mypy packages/contracts/python apps/api/src apps/workers/src tools/drone-simulator
	pnpm check-types

test: ## Run Python, JS/TS, Dart SDK, and Flutter test suites
	@uv run pytest || (code=$$?; [ $$code -eq 5 ] && echo "No pytest tests collected yet." || exit $$code)
	pnpm test
	@if [ -d packages/dart-sdk/test ]; then (cd packages/dart-sdk && dart test); else echo "No packages/dart-sdk/test directory yet."; fi
	@if [ -d apps/mobile/test ]; then (cd apps/mobile && flutter test); else echo "No apps/mobile/test directory yet."; fi

clean: ## Clear build, lint, and typecheck caches (keeps .venv, node_modules, volumes)
	pnpm clean
	rm -rf .mypy_cache .ruff_cache .pytest_cache
	cd apps/mobile && flutter clean