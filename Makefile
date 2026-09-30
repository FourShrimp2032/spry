.PHONY: up check deploy-frontend deploy-backend
up:
	docker compose up --build
check:
	cd backend && ruff check . && ruff format --check . && pytest
	cd frontend && npm ci && npm run lint && npm run format:check && npm run build
deploy-frontend:
	bash scripts/deploy-frontend.sh
deploy-backend:
	bash scripts/deploy-backend.sh
