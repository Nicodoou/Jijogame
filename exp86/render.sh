#!/bin/bash
# uso: exp86/render.sh <semilla> [mitad_ventana_studs] -> exp86/out/seed<N>.png
export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."
luau exp86/diag.luau -a $1 400 png ${2:-2000} > exp86/out/seed$1.txt
sed -n '/^PNGBEGIN/,/^PNGEND/p' exp86/out/seed$1.txt | grep -v PNG | tr -d '\n' | xxd -r -p > exp86/out/seed$1.png
grep -v "^[0-9a-f]\{100,\}" exp86/out/seed$1.txt | grep -v "^commit\|^stuck\|PNG"
