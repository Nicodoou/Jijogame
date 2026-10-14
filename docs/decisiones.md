# Decisiones

Registro de decisiones tomadas, la más nueva arriba. Formato en `docs/coordinacion-agentes.md`, sección 9.

Nada que esté en este registro se reabre sin un issue nuevo que explique por qué.

## 2026-10-14 — Reparto de áreas: Conducción para A, Calles infinitas para B
**Decidió:** ambos
**Issue:** #5
**Decisión:** el Agente A (con Nico) toma Conducción (`src/vehicle/`, `src/input/`, `src/camera/`, CP-1 a CP-16) y el Agente B (con Beni) toma Calles infinitas (`src/world/`, RC-1 a RC-12). Los issues #7 y #8 pasan a `para-agente-a` y los #9 y #10 a `para-agente-b`. En la tabla de contratos, el que provee o usa cada contrato cambia con el área; las firmas no cambian.
**Por qué:** Nico prefiere hacer el auto y Beni estuvo de acuerdo.
**Descartado:** la propuesta inicial de la coordinación (Calles infinitas para A, Conducción para B).

## 2026-10-14 — Los agentes mergean con aprobación de su persona
**Decidió:** Nico (pendiente de que Beni lo vea en el PR #11)
**Issue:** #11 (PR de setup)
**Decisión:** los merges a `main` los hacen los agentes A y B, cada uno con la aprobación explícita de su persona; si el PR toca un contrato o el área del otro, con la aprobación de las dos. El agente deja en el PR un comentario con quién aprobó.
**Por qué:** que los humanos no tengan que hacer el merge a mano, sin perder el control sobre qué entra a `main`.
**Descartado:** que solo los humanos mergeen (regla original de la coordinación).
