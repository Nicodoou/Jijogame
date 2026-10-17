#!/bin/bash
# uso: exp86/hashpar.sh <desde> <hasta> <tramos> <etiqueta> <variante> [procesos]
export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."
from=$1; to=$2; segs=$3; tag=$4; variant=$5; n=${6:-12}
total=$((to-from+1)); per=$(( (total+n-1)/n ))
rm -f exp86/out/h.$tag.*.txt
for ((i=0;i<n;i++)); do
  a=$((from+i*per)); b=$((a+per-1)); [ $b -gt $to ] && b=$to; [ $a -gt $to ] && break
  luau exp86/hash.luau -a $a $b $segs $variant > exp86/out/h.$tag.$i.txt 2>&1 &
done
wait
cat exp86/out/h.$tag.*.txt | sort -n > exp86/out/hash_$tag.txt
echo done $tag
