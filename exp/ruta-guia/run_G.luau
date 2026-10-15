-- uso: luau runone.luau <nombre>
local G = require("./guide")
local r = math.rad
local name = "G"
local presets = {
  A = {},
  B = {PSI_MAX = r(100)},
  C = {BACKTRACK = true},
  D = {GUIDE_ALTS = {30, 60, 90}},
  E = {PSI_MAX = r(100), BACKTRACK = true},
  F = {PSI_MAX = r(100), BACKTRACK = true, GUIDE_ALTS = {30, 60, 90}},
  G = {PSI_MAX = r(100), BACKTRACK = true, GUIDE_ALTS = {30, 60, 90}, LOCAL_DEV = 350, GUIDE_CLEARANCE = 1000},
  H = {LOCAL_DEV = 350, GUIDE_CLEARANCE = 1000},
  I = {PSI_MAX = r(100), BACKTRACK = true, GUIDE_ALTS = {30, 60}},
}
G.runConfig(name, presets[name], 40, 400)
