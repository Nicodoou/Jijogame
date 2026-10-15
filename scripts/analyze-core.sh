#!/usr/bin/env bash
# Chequeo de tipos del núcleo, los contratos y las pruebas con luau-lsp, sin globales de Roblox.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$ROOT_DIR" || fail "no existe $ROOT_DIR"
require_tools luau-lsp

files=()
while IFS= read -r file; do
	files+=("$file")
done < <(
	list_core_files
	list_contract_files
	list_test_files
)

echo "luau-lsp (standard): ${#files[@]} archivos"
luau-lsp analyze --platform=standard "${files[@]}"
