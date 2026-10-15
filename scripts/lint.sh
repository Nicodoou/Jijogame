#!/usr/bin/env bash
# Uso: scripts/lint.sh [core|adapters]   (sin argumento corre los dos)
#   core:     Selene con selene-core.toml (std luau, sin globales de Roblox) sobre el núcleo, los contratos y las pruebas.
#   adapters: Selene con selene.toml (std roblox) sobre el resto de src/.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CORE_CONFIG="$REPO_ROOT/selene-core.toml"
ADAPTERS_CONFIG="$REPO_ROOT/selene.toml"

cd "$ROOT_DIR" || fail "no existe $ROOT_DIR"
require_tools selene

# Corre Selene con la config $1 sobre los archivos que llegan por la entrada estándar.
run_selene() {
	local config files=()
	config="$(relative_path "$1")"
	while IFS= read -r file; do
		files+=("$file")
	done
	if [ "${#files[@]}" -eq 0 ]; then
		echo "selene ($2): no hay archivos."
		return 0
	fi
	echo "selene ($2): ${#files[@]} archivos"
	selene --config "$config" "${files[@]}"
}

lint_core() {
	{
		list_core_files
		list_contract_files
		list_test_files
	} | run_selene "$CORE_CONFIG" "núcleo, contratos y pruebas"
}

lint_adapters() {
	list_adapter_files | run_selene "$ADAPTERS_CONFIG" "adaptadores"
}

case "${1:-all}" in
core) lint_core ;;
adapters) lint_adapters ;;
all)
	status=0
	lint_core || status=1
	lint_adapters || status=1
	exit "$status"
	;;
*) fail "argumento desconocido '$1' (usá core o adapters)" ;;
esac
