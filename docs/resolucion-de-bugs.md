# Resolución de bugs

Ningún bug se arregla probando cosas. Este proceso existe para cortar el patrón de arreglar un bug, generar otro, arreglar el nuevo y terminar con parches sobre parches. Es obligatorio y cada paso queda escrito.

## Prohibido

- Cambiar código antes de haber replicado el bug.
- Arreglar el síntoma en vez de la causa: limitar un valor para que no se vea el error, envolver en `pcall` para tragarse una falla, agregar un `if` para el caso puntual.
- Probar varios cambios a la vez.
- Dejar en el código un intento que no funcionó.
- Dar un bug por resuelto porque "parece que ya no pasa", sin una prueba que lo demuestre.

## Roles

| Quién | Qué hace |
| --- | --- |
| Subagente | Analiza, aísla, replica, propone hipótesis, prueba, corrige y documenta |
| Opus | Aprueba las hipótesis antes de que se toque código y revisa la corrección |
| Persona | Decide cuando la corrección cambia el diseño, un contrato o el alcance del WP |

Todo el trabajo de un bug va en una rama `bug/<AAAA-MM-DD>-<tema>`.

## Proceso

### 0. ¿Es un bug?

Un bug es algo que contradice un requerimiento, un WP o una decisión documentada. Antes de buscar la causa, se demuestra esa contradicción.

- **La generación del mundo usa azar a propósito.** Antes de llamar bug a algo raro, se fija la semilla y se demuestra que el resultado viola una regla escrita.
- Si no contradice nada escrito, no es un bug: es un pedido de cambio y va como issue normal.

### 1. Analizar

Qué se esperaba, qué pasó y dónde dice que debería pasar lo esperado (requerimiento, WP o decisión).

### 2. Aislar

Reducir las condiciones al mínimo que sigue provocando el bug: qué semilla, qué tramo, qué velocidad, qué input, qué superficie. Se descarta todo lo que no influye.

### 3. Replicar

Lograr que el bug pase a voluntad, con pasos exactos.

- **La réplica queda como prueba automática que falla.** Así se sabe exactamente cuándo está resuelto, y el bug no puede volver sin que se note.
- **La física de Roblox no es determinista:** el mismo input no siempre da el mismo resultado. Si el bug depende de la física, se replica varias veces y se anota la frecuencia (por ejemplo, 7 de cada 10 intentos). La corrección tiene que llevar esa frecuencia a cero en la misma cantidad de intentos.
- Si no se puede automatizar, se documenta por qué y se escriben los pasos manuales exactos.

### 4. Hipótesis

Hasta 3 hipótesis, cada una con:

- **Causa:** qué está fallando, concreto.
- **Predicción:** "si la causa es X, al cambiar Y tiene que pasar Z".
- **Evidencia:** qué del análisis la sostiene.

El subagente frena y se las presenta a Opus. **No se toca código hasta que Opus las aprueba.** Si confirmar alguna implicaría cambiar el diseño, un contrato o el alcance del WP, Opus se lo lleva a la persona.

### 5. Instrumentar

Si hace falta más información, se agrega código de depuración temporal, marcado para poder encontrarlo y borrarlo:

```lua
-- DEBUG(bug-2026-10-20-reset-volcado)
```

Solo en la rama del bug. Nunca llega a un PR.

### 6. Probar

Una hipótesis por vez, con un solo cambio.

### 7. Confirmar o descartar

- **Confirmada:** la predicción se cumplió. Se pasa al paso 8.
- **Descartada:** se revierte todo el cambio, el código vuelve a estar exactamente como antes y se prueba la siguiente hipótesis.
- **Tres hipótesis descartadas seguidas:** se vuelve al paso 2. Probablemente el aislamiento estuvo mal o falta información.

### 8. Corregir la causa

Se corrige la causa, no el síntoma. La prueba del paso 3 tiene que pasar.

Si la corrección necesita otra corrección, se revierten las dos y se vuelve al paso 1.

### 9. Regresión

Antes de dar el bug por resuelto:

- Pasa la suite completa de pruebas.
- La cobertura sigue en el mínimo o por encima.
- Se repiten a mano las pruebas manuales relacionadas.
- Si el cambio toca código que corre por frame, se mide el rendimiento antes y después.

### 10. Limpiar

Se borra todo el código marcado con `DEBUG(...)` y cualquier rastro de las hipótesis descartadas.

### 11. Documentar

Se completa el archivo del bug y se agrega una línea en las notas rápidas si dejó algo que conviene saber.

## Archivo del bug

Cada bug tiene su archivo en `docs/bugs/<AAAA-MM-DD>-<tema>.md`:

```markdown
# Bug: título

**Issue:** #N
**Rama:** bug/AAAA-MM-DD-tema
**Estado:** abierto | aislado | replicado | hipótesis aprobadas | resuelto

## Por qué es un bug
Qué requerimiento, WP o decisión contradice.

## Esperado y observado

## Condiciones mínimas
Semilla, tramo, velocidad, input, superficie: lo que hace falta y nada más.

## Cómo replicarlo
1.

**Frecuencia:** siempre | X de cada N intentos
**Prueba que lo reproduce:** nombre, o por qué no se pudo automatizar.

## Hipótesis
### H1 — causa
- **Predicción:**
- **Evidencia:**
- **Aprobada por:** Opus | persona
- **Cambio probado:**
- **Resultado:** confirmada | descartada (revertida)

## Causa y corrección
Qué fallaba de verdad y qué se cambió.

## Regresión
- [ ] Suite completa
- [ ] Cobertura ≥ 87%
- [ ] Pruebas manuales relacionadas
- [ ] Rendimiento (si aplica)
- [ ] Código de depuración borrado

## Qué aprendimos
Qué conviene saber para que no vuelva a pasar algo parecido.
```
