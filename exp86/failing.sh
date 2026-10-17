#!/bin/bash
# uso: exp86/failing.sh <variante>  -> corre cada semilla de failing_seeds.txt (400 tramos) en su proceso
export PATH="$HOME/.rokit/bin:$PATH"
cd "$(dirname "$0")/.."
v=${1:-base}
for s in $(cat exp86/failing_seeds.txt | tr ',' ' '); do
  luau exp86/sweep.luau -a $s $s 400 $v > exp86/out/f.$s.txt 2>&1 &
done
wait
echo "variante=$v  encerradas: $(cat exp86/out/f.*.txt | grep -c '^ENCLOSED')/16"
cat exp86/out/f.*.txt | grep '^ENCLOSED'
cat exp86/out/f.*.txt | grep '^range' | awk '{for(i=1;i<=NF;i++){split($i,e,"="); if(e[1]=="worstStepMs"){v=e[2]+0; if(v>w)w=v}}} END{print "worstStepMs(contención)=" w}'
