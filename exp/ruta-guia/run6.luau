local G = require("./guide")
local r = math.rad
local runs = {
  {"A base", {}},
  {"B psi100", {PSI_MAX = r(100)}},
  {"C backtrack", {BACKTRACK = true}},
  {"D alts30-90", {GUIDE_ALTS = {30, 60, 90}}},
  {"E psi100+backtrack", {PSI_MAX = r(100), BACKTRACK = true}},
}
for _, run in runs do G.runConfig(run[1], run[2], 40, 400) end
