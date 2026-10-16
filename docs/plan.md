# Plan del proyecto

Lo que está en curso, lo que sigue, lo que queda para después del MVP y las preguntas que todavía no tienen respuesta. Cada agente mantiene la sección de su área y la actualiza al cerrar cada sesión (`docs/reglas-de-trabajo.md`, "El plan y las preguntas abiertas"). Lo que ya se decidió está en `docs/decisiones.md`; esto es lo que todavía no.

## Conducción (Agente A, con Nico)

### En curso
- **Primera vuelta por las calles reales:** Nico maneja el auto sobre el terreno del Agente B (PR #70) para encontrar problemas de la combinación.
- **Modelo del auto (#48):** Nico lo modela en Blockbench. Falta que la importación respete las piezas y su posición, y decidir si la física se adapta a la geometría del modelo.

### Próximo
1. **Retención en pendiente:** sin input, el auto rueda cuesta abajo. La decisión de diseño está pendiente con Nico (auto hold, un freno de mano más fuerte o las dos).
2. **Freno motor en la automática:** aprobado por Nico. Es un WP chico.
3. **Hitbox modular para el MVP:**
   - piezas exteriores con colisión y piezas interiores que se dañan a través de ellas;
   - un editor en Studio para ubicarlas.

   Primero hay que cerrar con Nico la lista de piezas y qué hace el daño. Después va un diseño completo (investigación, opciones y arquitectura).
4. **Reset (RC-12):** devolver el auto a la ruta, con el último punto válido y `GetNearestRoadPoint` (#35).
5. **Feedback (CP-13 a CP-16):** sonido del motor y de los neumáticos, polvo, marcas y HUD (el HUD cuenta solo el avance continuo, sin atajos).
6. **Bug #64:** inestabilidad por debajo de unos 25 FPS.

### Después del MVP
- **Motor por potencia, embrague, caja manual y acelerador como mariposa (#63).**
- **Autos y piezas intercambiables:** el auto como composición de fichas de datos (`EngineSpec`, `GearboxSpec`, `TireSpec`, `SuspensionSpec`, `ChassisSpec`, modelo visual), con un ensamblador puro que valida y produce la configuración del simulador, y el builder del modelo de Roblox. **Las bases se dejan asentadas en el MVP:** la hitbox modular nace como `ChassisSpec`, y los WPs nuevos no mezclan valores de piezas distintas.
- **Temperatura de neumáticos y frenos:** idea de Nico, descartada para el MVP.

### Preguntas de investigación abiertas
- **`PhysicsSteppingMethod`:** ¿`Fixed` contra `Adaptive`? ¿Cuál se siente mejor y es más estable? Prueba manual en Studio. Todavía no se confirmó si el valor del repo se aplica en vivo.
- **Costo en un celular de gama media:** cuánto cuestan los 4 rayos y el núcleo por frame. Prueba manual con un teléfono.
- **Estabilidad con FPS bajos (#64):** ¿cómo mantener el auto estable por debajo de 25 FPS? Hay que comparar subpasos del núcleo, un tope que considere la inercia de giro y un límite de `dt`. Primero con el investigador; después, experimento en el CLI.
- **Daño y colisiones por pieza:** ¿cómo detecta Roblox qué pieza chocó y con qué fuerza (`Touched`, consultas espaciales o las fuerzas de contacto)? ¿Cuánto cuesta con 20 o más hitboxes por auto? Primero el investigador y después un experimento en Studio.
- **Importación desde Blockbench:** ¿qué formato y qué opciones de Import 3D conservan las piezas separadas con su posición, sin armar un rig? Experimento con el modelo de Nico.
- **Geometría del auto:** ¿la física se adapta al modelo (ejes a 5,9 y ruedas de 0,81) o el modelo a la física? Hay que medir cómo cambia el manejo con una distancia entre ejes más corta. Prueba de juego con `Cfg_`, cuando se puedan sobrescribir tablas.

## Calles infinitas (Agente B, con Beni)

