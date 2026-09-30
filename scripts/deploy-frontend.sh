#!/usr/bin/env bash
set -euo pipefail
: "${AWS_REGION:?}" "${FRONTEND_BUCKET:?}" "${CLOUDFRONT_DISTRIBUTION_ID:?}" "${VITE_API_URL:?}"
[[ "$VITE_API_URL" == https://* ]] || { echo 'Production API must use HTTPS'; exit 1; }
(cd frontend && npm ci && npm run build)
# Publish new immutable assets first. Keep old hashed assets for already-open tabs.
aws s3 sync frontend/dist/assets/ "s3://$FRONTEND_BUCKET/assets/" --cache-control 'public,max-age=31536000,immutable'
aws s3 sync frontend/dist/ "s3://$FRONTEND_BUCKET/" --exclude 'assets/*' --cache-control 'no-cache'
aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" --paths '/*'
