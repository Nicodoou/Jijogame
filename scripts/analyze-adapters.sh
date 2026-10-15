#!/usr/bin/env bash
# Chequeo de tipos de los adaptadores (el resto de src/) con luau-lsp, el sourcemap de Rojo y las
# definiciones de Roblox que publica el repo de luau-lsp, fijadas a la versión de rokit.toml.
# Las definiciones pesan ~850 KB: se bajan una vez a .cache/ (que git ignora) y no se commitean.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PROJECT_FILE="default.project.json"
SOURCEMAP_FILE="sourcemap.json"
DEFINITIONS_URL_TEMPLATE="https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/%s/scripts/globalTypes.d.luau"

# Baja las definiciones de la versión fijada si todavía no están en el caché.
fetch_definitions() {
	local version url target
	version="$(tool_version luau-lsp)"
	[ -n "$version" ] || fail "no encuentro la versión de luau-lsp en rokit.toml"
	target="$CACHE_DIR/globalTypes-$version.d.luau"
	if [ ! -s "$target" ]; then
		# shellcheck disable=SC2059
		url="$(printf "$DEFINITIONS_URL_TEMPLATE" "$version")"
		mkdir -p "$CACHE_DIR"
		echo "Bajando las definiciones de Roblox de luau-lsp $version..." >&2
		curl --fail --silent --show-error --location --output "$target.tmp" "$url" || fail "no pude bajar $url"
		mv "$target.tmp" "$target"
	fi
	echo "$target"
}

cd "$ROOT_DIR" || fail "no existe $ROOT_DIR"
require_tools luau-lsp rojo curl

definitions="$(fetch_definitions)" || exit 1

files=()
while IFS= read -r file; do
	files+=("$file")
done < <(list_adapter_files)

if [ "${#files[@]}" -eq 0 ]; then
	echo "luau-lsp (roblox): no hay adaptadores que analizar."
	exit 0
fi

rojo sourcemap "$PROJECT_FILE" --include-non-scripts --output "$SOURCEMAP_FILE" || fail "rojo no pudo generar el sourcemap"
echo "luau-lsp (roblox): ${#files[@]} archivos"
luau-lsp analyze --platform=roblox --sourcemap="$SOURCEMAP_FILE" --definitions="$(relative_path "$definitions")" "${files[@]}"
