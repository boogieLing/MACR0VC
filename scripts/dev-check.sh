#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="${ROOT_DIR}/mac-client"
ENGINE_PYTHON="${ROOT_DIR}/engine/.venv/bin/python"

echo "[dev-check] running Swift tests"
pushd "${CLIENT_DIR}" >/dev/null
swift test
popd >/dev/null

if [[ -x "${ENGINE_PYTHON}" ]]; then
  echo "[dev-check] running Python engine regression tests"
  "${ENGINE_PYTHON}" -m unittest engine.tests.test_operation_state engine.tests.test_realtime_vc
else
  echo "[dev-check] skipped Python engine regression tests: ${ENGINE_PYTHON} not found" >&2
fi

echo "[dev-check] done"
