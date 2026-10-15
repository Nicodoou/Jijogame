#!/usr/bin/env bash
# Funciones y constantes compartidas por los scripts. Se usa con `source`, no se corre solo.
#
# RALLY_ROOT cambia la carpeta sobre la que trabajan los scripts (por defecto, la raíz del repo).
# Lo usa scripts/test-scripts.sh para correr los chequeos sobre los casos de tests/fixtures/.

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
ROOT_DIR="${RALLY_ROOT:-$REPO_ROOT}"

SOURCE_DIR="src"
TESTS_DIR="tests"
FIXTURES_DIR="tests/fixtures"
CONTRACTS_DIR="src/shared/contracts"
LUAU_EXTENSION="luau"
CACHE_DIR="$REPO_ROOT/.cache"
COVERAGE_DIR="coverage"

# Mensajes de error con el mismo formato en todos los scripts.
fail() {
	echo "ERROR: $*" >&2
	exit 1
}

# Falla con un mensaje claro si falta alguna herramienta en el PATH.
require_tools() {
	local tool
	for tool in "$@"; do
		command -v "$tool" >/dev/null 2>&1 || fail "no encuentro '$tool'. Corré 'rokit install' (ver docs/guia-de-desarrollo.md)."
	done
}

# Ruta de $1 relativa a la carpeta actual. Los ejecutables nativos de Windows no entienden las rutas de Git Bash.
relative_path() {
	realpath -m --relative-to="$PWD" "$1"
}

# Las listas de archivos se imprimen una por línea, ordenadas y relativas a ROOT_DIR.
list_core_files() {
	[ -d "$SOURCE_DIR" ] || return 0
	find "$SOURCE_DIR" -path "$SOURCE_DIR/*/core/*" -name "*.$LUAU_EXTENSION" | sort
}

list_contract_files() {
	[ -d "$CONTRACTS_DIR" ] || return 0
	find "$CONTRACTS_DIR" -name "*.$LUAU_EXTENSION" | sort
}

list_test_files() {
	[ -d "$TESTS_DIR" ] || return 0
	find "$TESTS_DIR" -name "*.$LUAU_EXTENSION" -not -path "$FIXTURES_DIR/*" | sort
}

list_adapter_files() {
	[ -d "$SOURCE_DIR" ] || return 0
	find "$SOURCE_DIR" -name "*.$LUAU_EXTENSION" -not -path "$SOURCE_DIR/*/core/*" -not -path "$CONTRACTS_DIR/*" | sort
}

# Versión de una herramienta fijada en rokit.toml del repo (por ejemplo: tool_version luau-lsp).
tool_version() {
	sed -n "s/^$1 *= *\"[^@]*@\(.*\)\"/\1/p" "$REPO_ROOT/rokit.toml"
}
