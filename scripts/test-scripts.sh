#!/usr/bin/env bash
# Prueba los chequeos con los casos de tests/fixtures/: cada chequeo tiene que FALLAR con su caso malo
# (y decir por qué) y PASAR con su caso bueno. Cada caso es un mini repo que se pasa por RALLY_ROOT.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FIXTURES_PATH="$REPO_ROOT/$FIXTURES_DIR"
GENERATED_NAMES=("$COVERAGE_DIR" "sourcemap.json" "coverage.out")

passed_count=0
failed_count=0

# Corre "$@" y guarda en $output lo que imprimió y en $status su código de salida.
run_captured() {
	output="$("$@" 2>&1)"
	status=$?
}

record_failure() {
	failed_count=$((failed_count + 1))
	echo "FALLA: $1" >&2
	echo "$output" | sed 's/^/    /' >&2
}

record_pass() {
	passed_count=$((passed_count + 1))
	echo "ok: $1"
}

# expect_fail "descripción" "texto que tiene que aparecer" comando...
expect_fail() {
	local description="$1" expected_text="$2"
	shift 2
	run_captured "$@"
	if [ "$status" -eq 0 ]; then
		record_failure "$description (tenía que fallar y terminó bien)"
	elif [[ "$output" != *"$expected_text"* ]]; then
		record_failure "$description (falló, pero el mensaje no dice '$expected_text')"
	else
		record_pass "$description"
	fi
}

# expect_pass "descripción" comando...
expect_pass() {
	local description="$1"
	shift
	run_captured "$@"
	if [ "$status" -ne 0 ]; then
		record_failure "$description (tenía que pasar y falló con código $status)"
	else
		record_pass "$description"
	fi
}

# expect_output "descripción" "texto" comando...  (pasa si termina bien y el texto aparece)
expect_output() {
	local description="$1" expected_text="$2"
	shift 2
	run_captured "$@"
	if [ "$status" -ne 0 ] || [[ "$output" != *"$expected_text"* ]]; then
		record_failure "$description (esperaba éxito con '$expected_text')"
	else
		record_pass "$description"
	fi
}

# in_fixture <caso> <script> [argumentos]: corre un script de scripts/ sobre el mini repo del caso.
in_fixture() {
	local fixture="$1" script="$2"
	shift 2
	RALLY_ROOT="$FIXTURES_PATH/$fixture" "$SCRIPTS_DIR/$script" "$@"
}

# Corre Luau-lsp con la plataforma estándar sobre un archivo de un caso.
analyze_standard() {
	(cd "$FIXTURES_PATH/$1" && luau-lsp analyze --platform=standard "$2")
}

clean_generated_files() {
	local fixture name
	for fixture in "$FIXTURES_PATH"/*/; do
		for name in "${GENERATED_NAMES[@]}"; do
			rm -rf "${fixture:?}${name:?}"
		done
	done
}

require_tools luau luau-lsp selene rojo
clean_generated_files

echo "== Núcleo que usa globales de Roblox"
expect_fail "selene del núcleo rechaza 'game'" "game" in_fixture core-uses-game lint.sh core
expect_fail "selene del núcleo rechaza Random" "Random" in_fixture core-uses-roblox-globals lint.sh core
expect_fail "selene del núcleo rechaza task" "task" in_fixture core-uses-roblox-globals lint.sh core
expect_fail "selene del núcleo rechaza Instance" "Instance" in_fixture core-uses-roblox-globals lint.sh core
expect_fail "selene del núcleo rechaza workspace" "workspace" in_fixture core-uses-roblox-globals lint.sh core
expect_fail "luau-lsp standard rechaza 'game' en el núcleo" "Unknown global 'game'" in_fixture core-uses-game analyze-core.sh

echo "== check-core.sh"
expect_fail "check-core rechaza un require a otra área" "sale del área 'a'" in_fixture check-core-require-other-area check-core.sh
expect_fail "check-core rechaza un require que no es un string" "no es un string" in_fixture check-core-require-dynamic check-core.sh
expect_fail "check-core rechaza un archivo sin --!strict" "--!strict" in_fixture check-core-no-strict check-core.sh
expect_fail "check-core rechaza Vector3" "Vector3" in_fixture check-core-vector3 check-core.sh
expect_fail "check-core rechaza una carpeta core/ fuera de src/<área>/core/" "fuera de" in_fixture check-core-outside check-core.sh
expect_fail "check-core exige --!strict en los contratos" "--!strict" in_fixture check-core-contract-no-strict check-core.sh

echo "== Núcleo bueno (vector, bit32, buffer y math.noise)"
expect_pass "selene del núcleo acepta la librería estándar de Luau" in_fixture core-good lint.sh core
expect_pass "check-core acepta el núcleo bueno" in_fixture core-good check-core.sh
expect_pass "luau-lsp standard acepta el núcleo bueno" in_fixture core-good analyze-core.sh
expect_pass "test.sh corre las pruebas del núcleo bueno" in_fixture core-good test.sh
expect_output "coverage.sh da 100% al núcleo bueno" "100.0%" in_fixture core-good coverage.sh

echo "== Cobertura"
expect_pass "test.sh termina bien si no hay pruebas" in_fixture coverage-untested test.sh
expect_fail "coverage.sh cuenta 0% un núcleo sin pruebas" "0.0%" in_fixture coverage-untested coverage.sh
expect_fail "coverage.sh lista las líneas sin cubrir" "Untested.luau:" in_fixture coverage-untested coverage.sh
expect_pass "test.sh corre el caso de borde" in_fixture coverage-border test.sh
expect_output "coverage.sh mide 87.5% en el caso de borde" "7/8 líneas = 87.5%" in_fixture coverage-border coverage.sh 87.5
expect_pass "coverage.sh pasa justo en el umbral (87.5)" in_fixture coverage-border coverage.sh 87.5
expect_fail "coverage.sh falla con el umbral apenas arriba (87.6)" "por debajo del umbral" in_fixture coverage-border coverage.sh 87.6
expect_fail "coverage.sh falla con el umbral 88" "por debajo del umbral" in_fixture coverage-border coverage.sh 88
expect_pass "coverage.sh pasa con el umbral apenas abajo (87.4)" in_fixture coverage-border coverage.sh 87.4
expect_pass "coverage.sh usa 87 por defecto y 87.5% lo cumple" in_fixture coverage-border coverage.sh
expect_fail "coverage.sh rechaza un umbral que no es un número" "umbral" in_fixture coverage-border coverage.sh abc
expect_output "coverage.sh sin archivos de núcleo no tiene nada que medir" "nada que medir" in_fixture runner-failing coverage.sh

echo "== Corredor de pruebas"
expect_fail "test.sh falla si una prueba falla y dice qué esperaba" "se esperaba 3 y se obtuvo 2" in_fixture runner-failing test.sh
expect_fail "test.sh dice qué prueba falló" "FALLA sums two numbers" in_fixture runner-failing test.sh
expect_fail "test.sh falla si el archivo no llama a Runner.finish()" "Runner.finish()" in_fixture runner-no-finish test.sh

echo "== Adaptadores (luau-lsp con las definiciones de Roblox)"
expect_pass "luau-lsp roblox acepta un adaptador que usa game, Instance y task" in_fixture adapter-good analyze-adapters.sh
expect_fail "luau-lsp standard no conoce 'game' (por eso los adaptadores usan roblox)" "Unknown global 'game'" analyze_standard adapter-good src/a/server/Spawner.luau
expect_fail "luau-lsp roblox rechaza un error de tipos en un adaptador" "TypeError" in_fixture adapter-bad analyze-adapters.sh

clean_generated_files
echo
echo "test-scripts: $passed_count OK, $failed_count con falla"
[ "$failed_count" -eq 0 ]
