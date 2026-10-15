#!/usr/bin/env bash
# Uso: scripts/coverage.sh [umbral]
# Calcula el porcentaje de líneas cubiertas de src/*/core/** con el reporte que dejó scripts/test.sh.
# Los archivos de núcleo que ninguna prueba carga no aparecen en el reporte: se cuentan con todas
# sus líneas ejecutables sin cubrir. Falla si el porcentaje queda por debajo del umbral.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DEFAULT_THRESHOLD=87
COMBINED_REPORT="$COVERAGE_DIR/combined.lcov"
MISSING_REPORT="$COVERAGE_DIR/missing.lcov"
PROBE_FILE="$COVERAGE_DIR/probe.luau"
RAW_COVERAGE_FILE="coverage.out"
CORE_PATH_REGEX='^src/[^/]+/core/'

threshold="${1:-$DEFAULT_THRESHOLD}"
[[ "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "el umbral tiene que ser un número (recibí '$threshold')"

cd "$ROOT_DIR" || fail "no existe $ROOT_DIR"

core_files=()
while IFS= read -r file; do
	core_files+=("$file")
done < <(list_core_files)

if [ "${#core_files[@]}" -eq 0 ]; then
	echo "No hay archivos en src/*/core: no hay nada que medir."
	exit 0
fi

[ -f "$COMBINED_REPORT" ] || fail "no existe $COMBINED_REPORT: corré scripts/test.sh antes."
require_tools luau

# Líneas ejecutables de un módulo que ninguna prueba cargó: se corre un archivo auxiliar que lo requiere
# y se toman las líneas que el reporte de luau le asigna. Se las cuenta todas como sin cubrir.
append_unloaded_file() {
	local file="$1"
	local module_path="../${file%."$LUAU_EXTENSION"}"
	printf 'require("%s")\n' "$module_path" >"$PROBE_FILE"
	rm -f "$RAW_COVERAGE_FILE"
	if ! output="$(luau --coverage "$PROBE_FILE" 2>&1)"; then
		fail "no pude determinar las líneas ejecutables de $file porque falla al cargarlo: $output"
	fi
	tr -d '\r' <"$RAW_COVERAGE_FILE" | tr '\134' '/' | awk -v target="$file" '
		/^SF:/ { current = substr($0, 4); sub(/^\.\//, "", current); inside = (current == target); if (inside) print "SF:" target; next }
		/^DA:/ && inside { split(substr($0, 4), pair, ","); print "DA:" pair[1] ",0"; next }
		/^end_of_record/ && inside { print "end_of_record"; inside = 0 }
	' >>"$MISSING_REPORT"
	rm -f "$RAW_COVERAGE_FILE"
}

: >"$MISSING_REPORT"
reported_files="$(tr -d '\r' <"$COMBINED_REPORT" | sed -n 's/^SF://p')"
for file in "${core_files[@]}"; do
	if ! grep -qxF "$file" <<<"$reported_files"; then
		echo "Sin pruebas que lo carguen: $file (cuenta como 0%)"
		append_unloaded_file "$file"
	fi
done

cat "$COMBINED_REPORT" "$MISSING_REPORT" | awk -v regex="$CORE_PATH_REGEX" -v threshold="$threshold" '
	/^SF:/ { file = substr($0, 4); measured = (file ~ regex); next }
	/^DA:/ && measured {
		split(substr($0, 4), pair, ",")
		total++
		if (pair[2] > 0) covered++
		else uncovered[++uncoveredCount] = file ":" pair[1]
	}
	END {
		if (total == 0) { print "Los archivos de src/*/core no tienen líneas ejecutables: nada que medir."; exit 0 }
		for (i = 1; i <= uncoveredCount; i++) print "sin cubrir: " uncovered[i]
		printf "Cobertura de src/*/core: %d/%d líneas = %.1f%% (umbral %s%%)\n", covered, total, 100 * covered / total, threshold
		if (covered * 100 < threshold * total) {
			print "ERROR: la cobertura está por debajo del umbral." > "/dev/stderr"
			exit 1
		}
	}
'
