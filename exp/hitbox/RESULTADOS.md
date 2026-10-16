# Experimento hitbox (exp/hitbox) - 2026-10-16

Studio "Experiencia sin título", en Play, con `execute_luau` (Server y Client). Rig propio en `Workspace.ExpHitbox`
(piso anclado a y=500 sin fricción, pared 100x40x4 en z=100, poste 0,5x40x0,5 en x=200, `Body` 6x2x10 de 84 de masa,
dueño de red = el jugador). Todo se borró al terminar; Studio quedó en Edit.
El scripting fue por `execute_luau` (contexto de plugin), salvo Q3 que usó un `Script` y un `LocalScript` reales.

## Q1 BindToCollisionSummaries
- Existe. Campos: Area, Normal, Part0, Part1, Point, RelativeVelocity, Time.
- Contra pared (cliente dueño de red): 30 -> relN=-30.00; 60 -> -60.00; 120 -> -120.00, un resumen por impacto, 2 corridas cada uno.
  Con `RelativeVelocity:Dot(Normal)` el signo depende del orden Part0/Part1 (-120 con la pared de Part1; +120 con el poste): usar el valor absoluto.
- Poste de 0,5: 8/8 a 120 con relN=120.0; 200 y 300 studs/s: 1 resumen cada uno, relN=200/300. Con el borde del auto sobre el poste a 120 llegaron 4 resúmenes (el primero con relN~0, rozando).
- Area: 12 a 30/60; en una corrida a 120 vino Area=0 (otra corrida 12). No usar Area como dato fiable.
- El piso genera resúmenes todos los frames (~40/s por contacto de apoyo): filtrar por Part1 / umbral.
- Cliente dueño: funciona. Enlazado en el servidor sobre la misma parte (dueño = cliente): 0 resúmenes en un choque contra la pared que el cliente sí recibió.

## Q2 30 cajas Massless soldadas (1,5^3, WeldConstraint, CanCollide=true)
Inercia por impulso angular 500 (I = L/omega), gravedad 0, Body + Ballast (densidad 5):
| caso | AssemblyMass | COM | Ix | Iy | Iz |
| sin cajas | 204.000 | (0, -0,882 rel. al centro) | 1209.95 | 1472.00 | 561.42 |
| 30 Massless | 204.000 | igual | 1210.21 | 1472.00 | 561.54 |
| 30 con masa (control) | 274.875 | (0,-0,655) | 2125.24 | 2592.89 | 937.38 |
Diferencia con Massless: masa 0, COM 0, inercia <=0,02 % (ruido de medición). El control con masa sí cambia todo.
Costo (Stats.PhysicsStepTimeMs, promedio 3 s, todas las cajas apoyadas en el piso, contacto constante):
- 10 autos (300 cajas): 3,5-4,0 ms sin enlazar vs 6,66 ms enlazadas (+~2,8 ms); callback mínimo 0,146 ms/frame.
- 1 auto (30 cajas): sin enlazar 1,25/0,78 vs enlazadas 0,67/1,05 ms: dentro del ruido (~±0,3 ms). Callback 0,006-0,010 ms/frame.
Escala aproximada ~0,01 ms por caja con contacto continuo.

## Q3 MeshPart.TextureID
- Pieza usada: MeshPart creada con `InsertService:CreateMeshPartAsync("rbxassetid://1095708")` (no había MeshParts en el lugar en esta sesión).
- `Script` (servidor): `TextureID = "rbxasset://textures/SpawnLocation.png"` -> sin error, valor leído después correcto; el cliente lo vio replicado.
- `LocalScript` (en PlayerGui): `TextureID = "rbxasset://textures/ui/GuiImagePlaceholder.png"` -> sin error, valor leído correcto (cambio solo local).
- NO confirmado: que el cambio se VEA en pantalla (la captura mostró la cámara del juego, no la pieza).

## Q4 Pieza que cae (Body 84, piezas 2x2x2 Massless soldadas, 60 studs/s, evento a 1,5 s)
Dueño de red (sondeado en el servidor cada 0,1 s, 5 s por corrida): Body, Piece1 y Piece2 = jugador en todo momento, en control, P1 y P2.
- P1 (Transparency 1 + CanCollide false + clon suelto en el cliente con la velocidad del auto): sin cambio de dueño, masa 84, velocidad final 60,0, costo del evento 0,13-0,26 ms. El clon quedó apoyado sobre el techo del Body (y=503,4, dz=0,44): no cayó porque lo puse arriba del auto; no probé caída al costado.
  Un pico de velocidad medido de ~41 studs/s en el frame del evento (vs ~8 sin evento); no pude separar si es el hitch de crear el clon o un golpe del clon al Body. Sin efecto persistente.
- P2 (WeldConstraint.Destroy() en el cliente): el Body quedó en 47,3 studs/s al final (arrastró/chocó con la pieza suelta, que quedó 31 studs atrás); la pieza se separó en el cliente pero el servidor sigue viendo la soldadura (`welded=true`) y la posición replicada de la pieza se alejó del Body (dz 3,0 -> -1,3 mientras el servidor aún la tenía soldada): estado inconsistente servidor/cliente. Dueño sin cambios.

## Limitaciones
- Todo con un solo cliente en Studio (sin latencia real). Rig propio, no el auto de Rojo (no había ModeloVisual en esta sesión).
- La métrica de "tirones" es cruda (velocidad por Heartbeat); no hay prueba visual.
- Q1 con Part0=Body siempre; no probado con cajas Massless enlazadas ni con ruedas/VectorForce.
