#!/usr/bin/env bash
# Corre todos los chequeos en el mismo orden que el CI. Sigue aunque uno falle y termina con error si falló alguno.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROJECT_FILE="default.project.json"
BUILD_OUTPUT="$CACHE_DIR/check-all-build.rbxl"

cd "$REPO_ROOT" || fail "no existe $REPO_ROOT"
require_tools stylua selene luau luau-lsp rojo curl

failed_steps=()

# run_step "nombre" comando...
run_step() {
	local name="$1"
	shift
	echo
	echo "=================== $name"
	if ! "$@"; then
		failed_steps+=("$name")
	fi
}

check_format() {
	stylua --check "$SOURCE_DIR" "$TESTS_DIR"
}

check_rojo_build() {
	mkdir -p "$CACHE_DIR"
	rojo build "$PROJECT_FILE" --output "$BUILD_OUTPUT"
}

run_step "Formato (stylua)" check_format
run_step "Lint (selene)" "$SCRIPTS_DIR/lint.sh"
run_step "Reglas del núcleo" "$SCRIPTS_DIR/check-core.sh"
run_step "Tipos del núcleo, contratos y pruebas (luau-lsp)" "$SCRIPTS_DIR/analyze-core.sh"
run_step "Tipos de los adaptadores (luau-lsp)" "$SCRIPTS_DIR/analyze-adapters.sh"
run_step "Pruebas de los scripts" "$SCRIPTS_DIR/test-scripts.sh"
run_step "Pruebas" "$SCRIPTS_DIR/test.sh"
run_step "Cobertura" "$SCRIPTS_DIR/coverage.sh"
run_step "Mapeo de Rojo (rojo build)" check_rojo_build

echo
if [ "${#failed_steps[@]}" -gt 0 ]; then
	echo "check-all: FALLARON ${#failed_steps[@]} chequeos:" >&2
	printf '  - %s\n' "${failed_steps[@]}" >&2
	exit 1
fi
echo "check-all: todo OK"
