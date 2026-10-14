# Pendiente de probar en Studio (otro agente)

Archivo a sincronizar con Rojo: `src/vehicle/core/Steering.luau` (requiere a `Clamp.luau`, su hermano).
Con `default.project.json` queda como `ReplicatedStorage.Vehicle.core.Steering` y `...core.Clamp`.

Hay que probar dos formas de `require` dentro de Steering (una por vez) y ver si Studio la resuelve:
1. `require("./Clamp")` (la que funciona en el CLI de Luau, 0.742.0, relativa al archivo que hace el require)
2. `require(script.Parent.Clamp)` (forma clasica de Roblox; no corre en el CLI)

Despues, desde un script en Studio: `require(game.ReplicatedStorage.Vehicle.core.Steering).angle(2, 30)` debe dar 30.
Tambien: `math.noise(0.5, 1.25, 2.75)` con `%.17g` y los valores de este experimento (ver informe).
