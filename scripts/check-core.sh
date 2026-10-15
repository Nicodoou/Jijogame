#!/usr/bin/env bash
# Reglas del núcleo (src/*/core/**) y de los contratos (src/shared/contracts/**) que Selene no ve:
#   1. La primera línea es --!strict.
#   2. No se usan Vector3 ni CFrame (el núcleo usa `vector`).
#   3. Todo require es un string relativo que apunta a la misma área o a src/shared/contracts/.
#   4. No existe ninguna carpeta core/ fuera de src/<área>/core/.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STRICT_HEADER="--!strict"
FORBIDDEN_WORDS=("Vector3" "CFrame")
NON_AREA_DIRS=("shared" "app")
CORE_DIR_NAME="core"
IGNORED_DIRS_FOR_CORE_SEARCH=(".git" "$FIXTURES_DIR" "node_modules" ".cache" "coverage")

violations=0

report_violation() {
	echo "ERROR $1: $2" >&2
	violations=$((violations + 1))
}

check_strict_header() {
	local file="$1"
	local first_line
	first_line="$(head -n 1 "$file" | tr -d '\r')"
	if [ "$first_line" != "$STRICT_HEADER" ]; then
		report_violation "$file:1" "la primera línea tiene que ser '$STRICT_HEADER' y es '$first_line'."
	fi
}

check_forbidden_words() {
	local file="$1"
	local word match
	for word in "${FORBIDDEN_WORDS[@]}"; do
		while IFS= read -r match; do
			[ -n "$match" ] || continue
			report_violation "$file:${match%%:*}" "el núcleo no puede usar '$word' (usá 'vector')."
		done < <(grep -nw -- "$word" "$file")
	done
}

# Área de un archivo de núcleo: src/<área>/core/... -> <área>.
area_of() {
	local rest="${1#"$SOURCE_DIR"/}"
	echo "${rest%%/*}"
}

check_requires() {
	local file="$1"
	local area directory match line argument target resolved
	area="$(area_of "$file")"
	directory="$(dirname "$file")"
	while IFS= read -r match; do
		[ -n "$match" ] || continue
		line="${match%%:*}"
		argument="$(sed -E 's/^[0-9]+:require[[:space:]]*\([[:space:]]*//; s/[[:space:]]*\)$//' <<<"$match")"
		if [[ "$argument" =~ ^\"([^\"]*)\"$ ]] || [[ "$argument" =~ ^\'([^\']*)\'$ ]]; then
			target="${BASH_REMATCH[1]}"
		else
			report_violation "$file:$line" "el require de '$argument' no es un string; en el núcleo solo se permite require(\"./X\") relativo."
			continue
		fi
		if [[ "$target" != ./* && "$target" != ../* ]]; then
			report_violation "$file:$line" "el require de \"$target\" no es relativo (tiene que empezar con ./ o ../)."
			continue
		fi
		resolved="$(realpath -m --relative-to="$PWD" "$directory/$target")"
		case "$resolved" in
		"$SOURCE_DIR/$area/"* | "$CONTRACTS_DIR/"*) ;;
		*) report_violation "$file:$line" "el require de \"$target\" sale del área '$area' (resuelve a '$resolved'); solo se permite la misma área o $CONTRACTS_DIR/." ;;
		esac
	done < <(grep -noE 'require[[:space:]]*\([^)]*\)' "$file")
}

check_core_directories() {
	local prune_args=() directory relative is_valid name
	for directory in "${IGNORED_DIRS_FOR_CORE_SEARCH[@]}"; do
		prune_args+=(-path "./$directory" -prune -o)
	done
	while IFS= read -r directory; do
		relative="${directory#./}"
		is_valid=false
		if [[ "$relative" =~ ^$SOURCE_DIR/([^/]+)/$CORE_DIR_NAME$ ]]; then
			is_valid=true
			for name in "${NON_AREA_DIRS[@]}"; do
				[ "${BASH_REMATCH[1]}" = "$name" ] && is_valid=false
			done
		fi
		if [ "$is_valid" = false ]; then
			report_violation "$relative" "carpeta '$CORE_DIR_NAME' fuera de $SOURCE_DIR/<área>/$CORE_DIR_NAME/: la cobertura no la mediría."
		fi
	done < <(find . "${prune_args[@]}" -type d -name "$CORE_DIR_NAME" -print)
}

cd "$ROOT_DIR" || fail "no existe $ROOT_DIR"

while IFS= read -r file; do
	check_strict_header "$file"
	check_forbidden_words "$file"
	check_requires "$file"
done < <(list_core_files)

while IFS= read -r file; do
	check_strict_header "$file"
done < <(list_contract_files)

check_core_directories

if [ "$violations" -gt 0 ]; then
	echo "check-core: $violations incumplimientos." >&2
	exit 1
fi
echo "check-core: OK"
