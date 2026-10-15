# Nombres del proyecto

Un concepto, un nombre. Se consulta antes de nombrar algo nuevo y se agrega acá cuando aparece un concepto nuevo.

| Concepto (español) | Nombre en código | Definición |
| --- | --- | --- |
| Tramo | `segment` | Porción de ruta generada como unidad, que se crea delante del auto y se libera detrás. |
| Superficie | `SurfaceKind` | Tipo de suelo en una posición del mundo; define cómo agarra el auto. Contrato en `src/shared/contracts/Surface.luau` (#17). |
| Ruta (superficie) | `"Road"` | Tierra compactada que ocupa todo el ancho de la ruta. |
| Banquina | `"Shoulder"` | Franja angosta de tierra suelta a cada lado de la ruta. |
| Pasto | `"Grass"` | Terreno al costado de la ruta. |
| Barro | `"Mud"` | Manchones fuera de la ruta, ubicados a partir de la semilla. |
| Posición del auto | `GetVehiclePosition` | Función que devuelve la posición actual del auto del jugador local. Contrato en `src/shared/contracts/VehiclePosition.luau` (#22). |
