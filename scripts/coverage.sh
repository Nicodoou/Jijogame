#!/usr/bin/env bash
# Uso: scripts/coverage.sh [coverage.out] [umbral]
# Calcula % de lineas cubiertas (DA con conteo > 0) de src/*/core/** y falla si es menor al umbral.
f="${1:-coverage.out}"; min="${2:-87}"
awk -v min="$min" '
/^SF:/ { p=substr($0,4); sub(/^\.\//,"",p); inc = (p ~ /^src\/[^\/]+\/core\//) }
/^DA:/ && inc { split(substr($0,4),a,","); t++; if (a[2]>0) c++; else print "sin cubrir: " p ":" a[1] }
END { if (!t) { print "sin lineas en src/*/core"; exit 2 }
      pct=100*c/t; printf "cobertura src/*/core: %d/%d = %.1f%% (umbral %s%%)\n", c, t, pct, min; exit (pct<min) }
' "$f"
