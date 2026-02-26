.PHONY: backend-install backend-test backend-lint frontend-install frontend-test frontend-lint frontend-build test lint compose-up compose-down terraform-fmt

backend-install:
	cd backend && npm install --no-audit --no-fund

backend-lint:
	cd backend && npm run lint

backend-test:
	cd backend && npm test

frontend-install:
	cd frontend && npm install --no-audit --no-fund

frontend-lint:
	cd frontend && npm run lint

frontend-test:
	cd frontend && npm test

frontend-build:
	cd frontend && npm run build

lint: backend-lint frontend-lint

test: backend-test frontend-test

compose-up:
	docker compose -f docker-compose.app.yml up -d --build

compose-down:
	docker compose -f docker-compose.app.yml down

terraform-fmt:
	cd infra/terraform && terraform fmt -recursive
