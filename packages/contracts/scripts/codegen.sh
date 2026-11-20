#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${CONTRACTS_DIR}/../.." && pwd)"

MQTT_DIR="${CONTRACTS_DIR}/mqtt"
OPENAPI_SPEC="${CONTRACTS_DIR}/openapi/openapi.json"
TS_GEN_DIR="${ROOT_DIR}/packages/ts-sdk/src/generated"
DART_SDK_DIR="${ROOT_DIR}/packages/dart-sdk"

CHECK_MODE=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_MODE=true
fi

mkdir -p "${TS_GEN_DIR}/mqtt" "${DART_SDK_DIR}/lib/src/generated"

echo "==> [contracts] Checking MQTT JSON Schemas in ${MQTT_DIR}..."
shopt -s nullglob
SCHEMA_FILES=("${MQTT_DIR}"/*.schema.json)
shopt -u nullglob

if [[ ${#SCHEMA_FILES[@]} -eq 0 ]]; then
  echo "    No *.schema.json files present yet (Phase 1 bootstrap). Skipping MQTT TS codegen."
else
  for schema_file in "${SCHEMA_FILES[@]}"; do
    base_name="$(basename "${schema_file}" .schema.json)"
    out_file="${TS_GEN_DIR}/mqtt/${base_name}.ts"
    echo "    Compiling ${base_name}.schema.json -> packages/ts-sdk/src/generated/mqtt/${base_name}.ts"
    pnpm --dir "${CONTRACTS_DIR}" exec json2ts \
      --input "${schema_file}" \
      --output "${out_file}" \
      --bannerComment "/* AUTO-GENERATED FROM packages/contracts/mqtt/${base_name}.schema.json — DO NOT EDIT */"
  done
fi

echo "==> [contracts] Checking OpenAPI 3.1 schema at ${OPENAPI_SPEC}..."
if [[ -f "${OPENAPI_SPEC}" ]]; then
  echo "    Compiling openapi.json -> packages/ts-sdk/src/generated/api.ts"
  pnpm --dir "${CONTRACTS_DIR}" exec openapi-typescript "${OPENAPI_SPEC}" \
    -o "${TS_GEN_DIR}/api.ts"
else
  echo "    No openapi.json exported yet (generated in Phase 2 from FastAPI). Skipping OpenAPI TS codegen."
fi

if [[ "${CHECK_MODE}" == "true" ]]; then
  echo "==> [contracts] Verifying zero contract drift..."
  if ! git -C "${ROOT_DIR}" diff --quiet -- packages/ts-sdk/src/generated packages/dart-sdk/lib/src/generated; then
    echo "ERROR: Generated SDKs are out of sync with packages/contracts. Run 'make codegen' and commit." >&2
    git -C "${ROOT_DIR}" status --short packages/ts-sdk/src/generated packages/dart-sdk/lib/src/generated
    exit 1
  fi
  echo "    OK: Generated SDKs match contracts."
fi