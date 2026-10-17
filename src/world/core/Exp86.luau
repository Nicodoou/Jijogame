--!nocheck
-- EXP86: perillas del experimento (descartable). Los valores por defecto reproducen el comportamiento de main.
return {
	diag = false,
	live = {},
	stats = { maxFail = 0, maxCount = 0, rerolls = 0, guideRescues = 0, guideMaxFail = 0 },
	onEnclosed = nil,
}
