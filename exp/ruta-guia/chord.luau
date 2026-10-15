local C = 400
for _, R in {60, 84, 180, 400, 1000, 2000, 3000, 5000} do
  local d = 401
  local chord = 2*R*math.sin(d/(2*R))
  print(string.format("R=%5d  cuerda de un arco de %d studs = %.1f  (%s)", R, d, chord, chord >= C and "libre" or "VIOLA"))
end
-- radio minimo para que un arco de 401 tenga cuerda >= 400
local lo, hi = 200, 1e6
for _=1,100 do local mid=(lo+hi)/2; if 2*mid*math.sin(401/(2*mid)) >= 400 then hi=mid else lo=mid end end
print("radio minimo admisible con la regla literal:", hi)
