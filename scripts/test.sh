#!/usr/bin/env bash
# Corre todos los tests/**/*.test.luau con cobertura y deja un único reporte combinado.
# Se corre desde cualquier carpeta; los archivos se ejecutan desde la raíz del repo, así las rutas del
# reporte quedan relativas a ella (src/<área>/core/X.luau) y los require relativos de las pruebas resuelven.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TEST_FILE_PATTERN="*.test.luau"
RAW_COVERAGE_FILE="coverage.out"
PARTS_DIR="$COVERAGE_DIR/parts"
COMBINED_REPORT="$COVERAGE_DIR/combined.lcov"
SUMMARY_MARKER="RESUMEN"

# Junta los reportes de cada archivo de prueba en uno solo, sumando los conteos de cada línea.
combine_reports() {
	{ cat "$PARTS_DIR"/*.out 2>/dev/null || true; } | tr -d '\r' | tr '\134' '/' | awk '
		/^SF:/ { file = substr($0, 4); sub(/^\.\//, "", file); next }
		/^DA:/ { split(substr($0, 4), pair, ","); counts[file " " pair[1]] += pair[2] }
		END { for (key in counts) print key, counts[key] }
	' | sort -k1,1 -k2,2n | awk '
		{
			if ($1 != current) {
				if (current != "") print "end_of_record"
				current = $1
				print "SF:" current
			}
			print "DA:" $2 "," $3
		}
		END { if (current != "") print "end_of_record" }
	' >"$COMBINED_REPORT"
}

cd "$ROOT_DIR" || fail "no existe $ROOT_DIR"
require_tools luau

rm -rf "$COVERAGE_DIR" "$RAW_COVERAGE_FILE"
mkdir -p "$PARTS_DIR"

failed_files=()
part_index=0
test_files=()
if [ -d "$TESTS_DIR" ]; then
	while IFS= read -r file; do
		test_files+=("$file")
	done < <(find "$TESTS_DIR" -name "$TEST_FILE_PATTERN" -not -path "$FIXTURES_DIR/*" | sort)
fi

for file in "${test_files[@]+"${test_files[@]}"}"; do
	echo "== $file"
	output="$(luau --coverage "$file" 2>&1)"
	status=$?
	printf '%s\n' "$output"
	if [ "$status" -ne 0 ]; then
		failed_files+=("$file")
	elif [[ "$output" != *"$SUMMARY_MARKER"* ]]; then
		echo "ERROR: $file terminó sin imprimir el resumen: le falta llamar a Runner.finish() al final." >&2
		failed_files+=("$file")
	fi
	if [ -f "$RAW_COVERAGE_FILE" ]; then
		part_index=$((part_index + 1))
		mv "$RAW_COVERAGE_FILE" "$PARTS_DIR/$part_index.out"
	fi
done

combine_reports || fail "no pude combinar los reportes de cobertura"

if [ "${#failed_files[@]}" -gt 0 ]; then
	echo "Fallaron ${#failed_files[@]} de ${#test_files[@]} archivos de prueba:" >&2
	printf '  %s\n' "${failed_files[@]}" >&2
	exit 1
fi
echo "Pruebas OK: ${#test_files[@]} archivos. Reporte de cobertura: $COMBINED_REPORT"
