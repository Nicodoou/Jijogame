# Motor, embrague y armado del auto (builder)

**Issue:** pedido de Nico (2026-10-17): "embrague, fuerza del motor, etc. Vamos a tener que tener una especie de builder para armar todas las combinaciones, ya que todos los motores van a ser compatibles con todos los autos". Retoma la idea #63.
**Requerimientos:**
- CP-4: la caja se siente.
- `requerimientos-mvp.md`: "Caja manual y embrague" está **fuera del MVP** (ver la decisión 1).

**Estado:** propuesta, para que la apruebe Nico.

## Lo que hay hoy
- **Una sola tabla:** `VehicleConfig` mezcla tres cosas:
  - el auto: ruedas, masa, centro de masa y suspensión;
  - el motor: `TORQUE_CURVE`, RPM y `FIRST_GEAR_PEAK_ACCELERATION`;
  - la caja: relaciones, diferencial, umbrales de cambio y kickdown.
- **Fuerza sin unidades físicas:** el motor no tiene potencia ni torque reales. La fuerza en la rueda es `masa · FIRST_GEAR_PEAK_ACCELERATION · fracción de la curva · (relación / relación de 1ra)`. Con eso, la aceleración no depende de la masa: un auto más pesado acelera igual.
- **Embrague implícito:** el corte de fuerza durante el cambio (`SHIFT_TORQUE_FRACTION` = 0).
- **Configuración inyectable:** se pasa por parámetro en todo el núcleo. El daño ya la reemplaza con `DamageEffects`, y eso es lo que hace posible un builder sin tocar el simulador.

## Lo que pide Nico
- **Motores intercambiables:** cualquier motor en cualquier auto, y cada combinación se maneja distinto.
- **Fuerza real del motor:** potencia en HP; la aceleración sale de potencia sobre peso.
- **Embrague:** un factor de 0 a 1 sobre la fuerza.
- **Freno motor:** el del WP-17, en `main`.

## Propuesta de arquitectura

Tres fichas de datos y una función pura que las arma:

```
CarSpec      (por auto: 147, …)    ruedas, masa del chasis, centro de masa, suspensión, modelo, ficha de daño
EngineSpec   (por motor)           curva de torque en N·m o "unidades de torque" contra RPM, ralentí, corte, masa del motor, freno motor
GearboxSpec  (por caja)            relaciones, diferencial, tipo (automática; manual después), umbrales, kickdown
             │
             ▼
VehicleBuild.assemble(car, engine, gearbox) → VehicleSettings
```

- **Salida:** `VehicleSettings` es la misma tabla que hoy consume el simulador. **El simulador no cambia.**
- **Otras capas que se componen igual:** `DamageEffects.apply` ya transforma `VehicleSettings`, y lo mismo pueden hacer los ajustes en vivo y los futuros upgrades.
- **Qué calcula `assemble`:**
  - **Masa total:** chasis + motor, y el centro de masa se corre según dónde va el motor. Un motor más pesado adelante carga más el eje delantero.
  - **Fuerza en la rueda desde el torque:** `F = torque(rpm) · relación · diferencial · eficiencia / radio de rueda`, en lugar de `FIRST_GEAR_PEAK_ACCELERATION`. Así, un auto más pesado con el mismo motor acelera menos.
  - **Velocidad máxima y corte por marcha:** se derivan del corte y las relaciones, como hoy.
  - **Validación:** si una combinación no tiene sentido (sin marchas, curva vacía o masa ≤ 0), devuelve error con la razón, no un auto roto.
- **Patrones:**
  - **Builder:** las fichas se combinan en una sola configuración.
  - **Datos sin lógica:** las fichas son tablas.
  - **Función pura:** se prueba en el CLI.
- **Unidades:** Roblox no tiene unidades físicas reales. Hay dos opciones (decisión 2):
  - **a)** "HP de juego", calibrados para que el 147 con su motor actual acelere igual que hoy;
  - **b)** conversión a unidades reales, con 1 stud = 0,28 m y masa de Roblox a kg, que da números raros y frágiles.

### Embrague (en la automática)
- **Factor en el arranque:** factor de embrague de 0 a 1 en el núcleo de la caja. En la automática es automático: patina al arrancar desde quieto (sube de 0 a 1 según RPM y velocidad) y se abre en el cambio, que es el corte actual pero con una rampa en vez de un escalón.
- **Freno motor:** el del WP-17 pasa a usar el mismo factor. Con el embrague abierto no hay freno motor.
- **Manual:** la caja manual y el pedal de embrague quedan para después del MVP (decisión 1). La arquitectura los deja preparados: `GearboxSpec.kind = "manual"` y una entrada `clutch` en los controles.

## Opciones y decisiones

### Decisión 1: caja manual y pedal de embrague
- **M1. Fuera del MVP (recomendada).** Así lo dice `requerimientos-mvp.md`. En el MVP solo va el embrague automático interno. La arquitectura ya los contempla.
- **M2. Adentro del MVP.** Cambia los requerimientos y suma input (teclas de cambio y embrague), interfaz de la marcha y pruebas de manejo.

### Decisión 2: unidades del motor
- **U1. "HP de juego" calibrados (recomendada).** El motor del 147 actual es la referencia (por ejemplo, 50 HP de juego). Los números son legibles, se comparan entre motores y no dependen de la conversión de Roblox.
- **U2. Unidades reales.** Más "auténtico", pero la masa de Roblox no es kg y las fuerzas se vuelven difíciles de leer.

### Decisión 3: dónde viven las fichas
- **F1. `src/vehicle/core/specs/` (recomendada):** una carpeta `cars/`, otra `engines/` y otra `gearboxes/`, con un archivo por ficha. Son datos del núcleo y se validan en el CLI.
- **F2. En Studio, como atributos de instancias.** Es más fácil de editar sin código, pero no se prueba en el CLI y no pasa por PR.

### Decisión 4: quién elige la combinación
- **E1. En el MVP, una combinación fija** (147 + motor del 147 + automática) desde el arranque. El servidor la elige y la replica.
- **E2. Selección en el juego (garage).** Necesita interfaz y guardado. Va después del MVP, con la reparación.

Recomiendo **E1**: el builder queda probado con varias combinaciones en las pruebas, pero el juego usa una.

### Decisión 5: migración
- **Paso 1.** `VehicleConfig` pasa a armarse con `VehicleBuild.assemble(Fiat147, Engine147, Automatic5)`, con valores elegidos para que el auto **se maneje exactamente igual que hoy**. La prueba que lo cierra: todas las propiedades del simulador pasan sin tocarlas, y la fuerza en la rueda en cada marcha y RPM coincide con la de hoy (±1%).
- **Paso 2.** Agregar un segundo motor (por ejemplo, uno más potente y pesado) y pruebas que muestren que la combinación cambia la aceleración, la velocidad máxima y el reparto de peso como se espera.
- **Paso 3.** El embrague automático con rampa.

## Plan de trabajo
1. **WP-20a:** fichas, `VehicleBuild.assemble` y la migración sin cambio de manejo (paso 1). Solo núcleo.
2. **WP-20b:** segundo motor y pruebas de combinaciones (paso 2).
3. **WP-20c:** embrague automático con rampa y freno motor con embrague (paso 3). Lo prueba Nico manejando.

## Riesgos
- **Que la migración cambie el manejo:** el paso 1 exige igualdad ±1% en la fuerza y que todas las propiedades pasen.
- **Que la masa nueva cambie la estabilidad (bug de vibración del WP-7):** el lastre se calcula desde la masa total. Se mide la inercia en Studio.
- **Que `VehicleConfig` deje de ser una tabla literal:** los ajustes en vivo (`Cfg_`) siguen funcionando porque se aplican sobre la salida del builder.
