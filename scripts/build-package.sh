#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="@defi-wonderland/aztec-standards"
EXPORT_DIR="export/${PROJECT_NAME}"

# ── Compile artifacts to JS ──────────────────────────────────────────────────
mkdir -p dist/artifacts/
yarn tsc src/artifacts/*.ts --outDir dist/artifacts/ --skipLibCheck --target es2020 --module nodenext --moduleResolution nodenext --resolveJsonModule --declaration

# ── Inspect contracts ────────────────────────────────────────────────────────
for f in target/*.json; do
  [ -f "$f" ] || continue
  aztec inspect-contract "$f"
done

# ── Prepare export directory ─────────────────────────────────────────────────
mkdir -p "${EXPORT_DIR}/artifacts"
mkdir -p "${EXPORT_DIR}/dist"

# Copy compiled JS artifacts
cp -r dist/artifacts/* "${EXPORT_DIR}/artifacts/"

# Copy compiled JS artifacts to dist/ (for pre-release dist.tar.gz)
cp -r dist/artifacts/* "${EXPORT_DIR}/dist/"

# Copy compiled Noir contracts
cp -r target "${EXPORT_DIR}/"

# Copy deployments.json if it exists
if [ -f "src/deployments.json" ]; then
  cp src/deployments.json "${EXPORT_DIR}/"
else
  echo "src/deployments.json not found, skipping"
fi

# Copy documentation
cp README.md "${EXPORT_DIR}/"
cp LICENSE "${EXPORT_DIR}/"

# Create trimmed package.json (strip dev-only fields)
jq 'del(.scripts, .jest, ."lint-staged", .packageManager, .devDependencies, .dependencies, .engines, .resolutions)' \
  package.json > "${EXPORT_DIR}/package.json"

echo "✔ Package prepared at ${EXPORT_DIR}"
