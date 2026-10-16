--!strict
-- Convierte un valor crudo en su cuantil (u en [0, 1]) con una tabla de percentiles medida: la entrada `index` de una
-- tabla de N entradas es el valor que deja a su izquierda la fracción (index - 1) / (N - 1) de las muestras.

local QuantileMap = {}

function QuantileMap.toUnit(value: number, table: { number }): number
	if value ~= value then
		error("the value to normalize cannot be NaN", 2)
	end
	local lastIndex = #table
	if value <= table[1] then
		return 0
	elseif value >= table[lastIndex] then
		return 1
	end
	-- Invariante: table[low] <= value < table[high].
	local low, high = 1, lastIndex
	while high - low > 1 do
		local middle = (low + high) // 2
		if table[middle] <= value then
			low = middle
		else
			high = middle
		end
	end
	local span = table[high] - table[low]
	local fractionInside = (value - table[low]) / span
	return (low - 1 + fractionInside) / (lastIndex - 1)
end

return QuantileMap
