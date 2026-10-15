local G = require("./guide")
for _, np in {1200, 900, 700, 500} do
  G.runConfig("NEIGH_PREVIEW=" .. np, {NEIGH_PREVIEW = np}, 40, 400)
end
