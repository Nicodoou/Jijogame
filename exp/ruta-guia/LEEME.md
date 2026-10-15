# Experimento: ruta de rally con guía grande (#37)

Rama descartable (`exp/`): no se mergea y su código no se reutiliza tal cual.

- `chord.luau`: la cuerda de un arco de 401 studs según el radio. Muestra que la regla anti-cruce original del WP-5 (vecindad = distancia libre = 400) es imposible.
- `guide.luau`: prototipo de "guía grande + curvas locales", con anti-cruce corregido, salida de emergencia, rumbo relativo acotado y retroceso de la guía y de la ruta.
- `run*.luau`: las corridas. `out*.txt`: sus salidas (configuraciones A a I; E y G con 200 semillas × 400 tramos).

Resultado: la configuración G (rumbo relativo ≤ 100°, retroceso de la ruta de 1 a 3 piezas, guía sin ±120°, túnel de ±350 y `GUIDE_CLEARANCE` de 1000) da 0 encerradas y 0 violaciones en 200 semillas × 400 tramos. El resumen está en `docs/disenos/ruta.md`, en la revisión de la arquitectura por #37.
