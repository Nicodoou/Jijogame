--!strict
-- Perfil de cerros: la altura de la ruta en función de su arcLength. El ruido (varias octavas de math.noise, con
-- desplazamiento sorteado por la semilla) da una altura objetivo, y la pendiente la sigue con tres límites: la
-- pendiente máxima, el cambio máximo por paso y la franja de alturas. Todo depende solo de la altura, la pendiente y el
-- arcLength, así que no cambia con el trazado en el plano.

local SeededRandom = require("./SeededRandom")
local WorldConfig = require("./WorldConfig")

export type HillSettings = {
	baseHeightStuds: number,
	amplitudeStuds: number,
	wavelengthStuds: number,
	octaves: number,
	minHeightStuds: number,
	maxHeightStuds: number,
	maxSlopeRadians: number,
	maxSlopeChangeRadiansPerStep: number,
	lookaheadStuds: number,
	amplitudeFactor: number,
	wavelengthFactor: number,
}

export type HillProfile = {
	-- Altura a la que apunta la ruta en ese arcLength, ya dentro de la franja.
	getTargetHeight: (arcLength: number) -> number,
	-- Pendiente (radianes) de la próxima muestra, dadas la altura y la pendiente de la actual y su arcLength.
	nextSlope: (currentHeight: number, currentSlope: number, arcLength: number) -> number,
}

local STEP_STUDS = WorldConfig.INTEGRATION_STEP_STUDS
local HALF = 0.5
-- Iteraciones de la bisección que busca la mayor pendiente que aún deja frenar dentro de la franja.
local BISECTION_ITERATIONS = 24
local NOISE_AXIS_COUNT = 2
local NOISE_DIRECTION_RADIANS = math.rad(WorldConfig.HILL_NOISE_DIRECTION_DEGREES)
local NOISE_STEP_X = math.cos(NOISE_DIRECTION_RADIANS)
local NOISE_STEP_Y = math.sin(NOISE_DIRECTION_RADIANS)

local defaultSettings: HillSettings = table.freeze({
	baseHeightStuds = WorldConfig.HILL_BASE_HEIGHT_STUDS,
	amplitudeStuds = WorldConfig.HILL_AMPLITUDE_STUDS,
	wavelengthStuds = WorldConfig.HILL_WAVELENGTH_STUDS,
	octaves = WorldConfig.HILL_OCTAVES,
	minHeightStuds = WorldConfig.HILL_MIN_HEIGHT_STUDS,
	maxHeightStuds = WorldConfig.HILL_MAX_HEIGHT_STUDS,
	maxSlopeRadians = math.rad(WorldConfig.MAX_SLOPE_DEGREES),
	maxSlopeChangeRadiansPerStep = math.rad(WorldConfig.HILL_MAX_SLOPE_CHANGE_DEGREES_PER_STEP),
	lookaheadStuds = WorldConfig.HILL_LOOKAHEAD_STUDS,
	amplitudeFactor = WorldConfig.HILL_OCTAVE_AMPLITUDE_FACTOR,
	wavelengthFactor = WorldConfig.HILL_OCTAVE_WAVELENGTH_FACTOR,
})

-- Altura que todavía se sube si la pendiente (>= 0) baja a cero con el máximo cambio por paso.
local function getBrakingClimb(slope: number, maxChange: number): number
	local climb = 0
	local current = slope
	while current > 0 do
		local following = math.max(0, current - maxChange)
		climb += STEP_STUDS * math.tan(HALF * (current + following))
		current = following
	end
	return climb
end

-- Si la próxima muestra tiene pendiente `candidate`, la altura sigue dentro de `headroom` (el espacio que queda hacia
-- arriba) aunque desde ahí se frene al máximo.
local function fitsInHeadroom(config: HillSettings, currentSlope: number, candidate: number, headroom: number): boolean
	local climbNow = STEP_STUDS * math.tan(HALF * (currentSlope + candidate))
	local brakingClimb = getBrakingClimb(math.max(candidate, 0), config.maxSlopeChangeRadiansPerStep)
	return climbNow + brakingClimb <= headroom
end

local function createNoiseOffsets(seed: number, octaves: number): { { number } }
	local random = SeededRandom.new(seed)
	local offsets = {}
	for octave = 1, octaves do
		local axes = {}
		for axis = 1, NOISE_AXIS_COUNT do
			-- Un desplazamiento entero pondría las muestras sobre la grilla del ruido, donde vale siempre 0.
			axes[axis] = math.floor(random.nextNumber() * WorldConfig.HILL_NOISE_OFFSET_RANGE) + HALF
		end
		offsets[octave] = axes
	end
	return offsets
end

local HillProfileModule = {}

HillProfileModule.defaultSettings = defaultSettings

function HillProfileModule.new(seed: number, settings: HillSettings?): HillProfile
	local config = settings or defaultSettings
	local offsets = createNoiseOffsets(seed, config.octaves)

	local function getTargetHeight(arcLength: number): number
		local sum = 0
		local amplitude = config.amplitudeStuds
		local wavelength = config.wavelengthStuds
		for octave = 1, config.octaves do
			local axes = offsets[octave]
			local travel = arcLength / wavelength
			sum += amplitude * math.noise(travel * NOISE_STEP_X + axes[1], travel * NOISE_STEP_Y + axes[2])
			amplitude *= config.amplitudeFactor
			wavelength *= config.wavelengthFactor
		end
		return math.clamp(config.baseHeightStuds + sum, config.minHeightStuds, config.maxHeightStuds)
	end

	-- Por encima de este espacio de altura, ningún borde de la franja puede estar activo.
	local freeHeadroom = STEP_STUDS * math.tan(config.maxSlopeRadians)
		+ getBrakingClimb(config.maxSlopeRadians, config.maxSlopeChangeRadiansPerStep)

	-- La mayor pendiente de la próxima muestra (hasta `wanted`) que todavía deja frenar sin pasar del borde.
	local function limitByHeadroom(currentSlope: number, wanted: number, headroom: number): number
		if headroom > freeHeadroom or fitsInHeadroom(config, currentSlope, wanted, headroom) then
			return wanted
		end
		local safe, unsafe = currentSlope - config.maxSlopeChangeRadiansPerStep, wanted
		for _ = 1, BISECTION_ITERATIONS do
			local middle = HALF * (safe + unsafe)
			if fitsInHeadroom(config, currentSlope, middle, headroom) then
				safe = middle
			else
				unsafe = middle
			end
		end
		return safe
	end

	local function nextSlope(currentHeight: number, currentSlope: number, arcLength: number): number
		local aimedHeight = getTargetHeight(arcLength + config.lookaheadStuds)
		local wanted = math.atan((aimedHeight - currentHeight) / config.lookaheadStuds)
		wanted = math.clamp(wanted, -config.maxSlopeRadians, config.maxSlopeRadians)
		wanted = math.clamp(
			wanted,
			currentSlope - config.maxSlopeChangeRadiansPerStep,
			currentSlope + config.maxSlopeChangeRadiansPerStep
		)
		wanted = limitByHeadroom(currentSlope, wanted, config.maxHeightStuds - currentHeight)
		-- Hacia abajo es lo mismo con los signos invertidos.
		return -limitByHeadroom(-currentSlope, -wanted, currentHeight - config.minHeightStuds)
	end

	return { getTargetHeight = getTargetHeight, nextSlope = nextSlope }
end

return HillProfileModule
