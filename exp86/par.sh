#!/bin/bash
# uso: exp86/par.sh <desde> <hasta> <tramos> <etiqueta> [variante] [procesos]
export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."
from=$1; to=$2; segs=$3; tag=$4; variant=${5:-base}; n=${6:-14}
total=$((to-from+1)); per=$(( (total+n-1)/n ))
rm -f exp86/out/$tag.*.txt
start=$(date +%s)
for ((i=0;i<n;i++)); do
  a=$((from+i*per)); b=$((a+per-1)); [ $b -gt $to ] && b=$to; [ $a -gt $to ] && break
  luau exp86/sweep.luau -a $a $b $segs $variant > exp86/out/$tag.$i.txt 2>&1 &
done
wait
echo "== $tag variant=$variant seeds=$from-$to segs=$segs wall=$(( $(date +%s)-start ))s"
cat exp86/out/$tag.*.txt | grep "^ENCLOSED" | sort -t= -k2 -n
cat exp86/out/$tag.*.txt | awk '
/^variant/ {for(i=2;i<=NF;i++){split($i,e,"="); if(e[1]=="maxFailBeforeAdvance"&&e[2]+0>mf)mf=e[2]+0; if(e[1]=="maxRetractedAtOnce"&&e[2]+0>mc)mc=e[2]+0}}
/^range/ {for(i=1;i<=NF;i++){split($i,e,"="); if(e[1]=="enclosed")s+=e[2]; if(e[1]=="exposure")x+=e[2]; if(e[1]=="worstStepMs"){v=e[2]+0; if(v>w)w=v}}}
/^variant/ {split($0,h,"="); n=split(h[length(h)],hh,"/"); for(i=1;i<=n;i++) H[i]+=hh[i]}
END{print "seedsWithMaxFailOver10/30/100/300=" H[1] "/" H[2] "/" H[3] "/" H[4]; print "TOTAL enclosed=" s " exposureSegments=" x " worstStepMs=" w " maxFailBeforeAdvance=" mf " maxRetractedAtOnce=" mc}'
