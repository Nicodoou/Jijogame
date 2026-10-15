--!strict
-- Generador pseudoaleatorio de 32 bits (xoshiro128**) con estado explícito.
-- Usa solo bit32 y aritmética entera exacta en dobles: nada de multiplicaciones de 64 bits.

export type SeededRandom = {
	nextNumber: () -> number,
	nextInteger: (minimum: number, maximum: number) -> number,
	clone: () -> SeededRandom,
}

local WORD_RANGE = 4294967296
local HALF_WORD_RANGE = 65536
local HALF_WORD_BITS = 16
local HASH_SHIFT_BITS = 15
local SEED_INCREMENT = 0x9E3779B9
local HASH_MULTIPLIER_FIRST = 0x21F0AAAD
local HASH_MULTIPLIER_SECOND = 0x735A2D97
local STATE_WORD_COUNT = 4
local OUTPUT_MULTIPLIER_FIRST = 5
local OUTPUT_MULTIPLIER_SECOND = 9
local OUTPUT_ROTATION_BITS = 7
local STATE_SHIFT_BITS = 9
local STATE_ROTATION_BITS = 11
-- Mayor magnitud del exponente de un double subnormal; deja el exponente no negativo.
local EXPONENT_OFFSET = 1100

-- (a * b) mod 2^32 sin pasar de 2^53: se parte `a` en dos mitades de 16 bits.
local function multiplyWords(left: number, right: number): number
	local highHalf = bit32.rshift(left, HALF_WORD_BITS)
	local lowHalf = bit32.band(left, HALF_WORD_RANGE - 1)
	local highPart = (highHalf * right) % HALF_WORD_RANGE
	return (lowHalf * right + highPart * HALF_WORD_RANGE) % WORD_RANGE
end

local function hashWord(word: number): number
	local mixed = multiplyWords(bit32.bxor(word, bit32.rshift(word, HALF_WORD_BITS)), HASH_MULTIPLIER_FIRST)
	mixed = multiplyWords(bit32.bxor(mixed, bit32.rshift(mixed, HASH_SHIFT_BITS)), HASH_MULTIPLIER_SECOND)
	return bit32.bxor(mixed, bit32.rshift(mixed, HASH_SHIFT_BITS))
end

-- Descompone el double en mantisa, exponente y signo, así dos semillas distintas no dan las mismas palabras
-- (las enormes valdrían todas 0 en la parte entera módulo 2^32).
local function foldSeed(seed: number): number
	local mantissa, exponent = math.frexp(math.abs(seed))
	local scaledMantissa = mantissa * WORD_RANGE
	local highWord = math.floor(scaledMantissa)
	local lowWord = math.floor((scaledMantissa - highWord) * WORD_RANGE)
	local signWord = if seed < 0 then 1 else 0
	local exponentWord = exponent + EXPONENT_OFFSET
	local folded = hashWord(signWord)
	folded = hashWord(bit32.bxor(folded, exponentWord))
	folded = hashWord(bit32.bxor(folded, lowWord))
	return hashWord(bit32.bxor(folded, highWord))
end

local function createFromState(first: number, second: number, third: number, fourth: number): SeededRandom
	local state0, state1, state2, state3 = first, second, third, fourth

	local function nextWord(): number
		local scrambled = bit32.lrotate((state1 * OUTPUT_MULTIPLIER_FIRST) % WORD_RANGE, OUTPUT_ROTATION_BITS)
		local result = (scrambled * OUTPUT_MULTIPLIER_SECOND) % WORD_RANGE
		local shifted = bit32.lshift(state1, STATE_SHIFT_BITS)
		state2 = bit32.bxor(state2, state0)
		state3 = bit32.bxor(state3, state1)
		state1 = bit32.bxor(state1, state2)
		state0 = bit32.bxor(state0, state3)
		state2 = bit32.bxor(state2, shifted)
		state3 = bit32.lrotate(state3, STATE_ROTATION_BITS)
		return result
	end

	local function nextNumber(): number
		return nextWord() / WORD_RANGE
	end

	local function nextInteger(minimum: number, maximum: number): number
		if math.floor(minimum) ~= minimum or math.floor(maximum) ~= maximum then
			error("nextInteger needs integer bounds", 2)
		end
		local count = maximum - minimum + 1
		if count < 1 or count > WORD_RANGE then
			error("nextInteger needs minimum <= maximum and a range of at most 2^32 values", 2)
		end
		return minimum + math.floor(nextNumber() * count)
	end

	local function clone(): SeededRandom
		return createFromState(state0, state1, state2, state3)
	end

	return { nextNumber = nextNumber, nextInteger = nextInteger, clone = clone }
end

local SeededRandom = {}

function SeededRandom.new(seed: number): SeededRandom
	if seed ~= seed or math.abs(seed) == math.huge then
		error("the seed has to be a finite number", 2)
	end
	local stream = foldSeed(seed)
	local words = table.create(STATE_WORD_COUNT, 0)
	for index = 1, STATE_WORD_COUNT do
		stream = (stream + SEED_INCREMENT) % WORD_RANGE
		words[index] = hashWord(stream)
	end
	return createFromState(words[1], words[2], words[3], words[4])
end

return SeededRandom
