# Plan de implementación — Visor multiplayer de objetos 3D ("Arquitecto")

> Documento vivo. Última actualización: 2026-06-01.

## 1. Objetivo y alcance

Aplicación 3D en la que varios alumnos, en la **misma red local del aula**, se mueven con
un personaje (avatar Mixamo) por un escenario que contiene **objetos modelados en
Tinkercad / FreeCAD / SketchUp**. El fin es **visualizar y recorrer en grupo** esas
creaciones.

- **Multijugador**: LAN, sin internet ni servidores externos.
- **Distribución**: un **ejecutable Linux** que el profesor copia a mano a cada equipo.
- **Equipos destino**: ordenadores con **EducandOS** (Linux, base Debian). Política
  "se puede ejecutar pero no instalar".
- **Fuera de alcance** (por ahora): física compleja, edición de objetos en vivo,
  persistencia/guardado, internet/online, chat de voz.

## 2. Stack y decisiones técnicas fijadas

| Área | Decisión | Motivo |
|---|---|---|
| Motor | **Godot 4.4** | Multiplayer de alto nivel integrado, export Linux sencillo. |
| Renderer | **Compatibility (GLES3/OpenGL)** | Hardware de aula modesto / GPUs integradas. |
| Red | **ENet** (UDP fiable) sobre **LAN** | Sólido, sin servidores externos. |
| Topología | **Listen-server**: un equipo hospeda y juega | Cero infraestructura. |
| Descubrimiento | **Broadcast UDP** en LAN | Los alumnos ven el servidor en una lista, sin teclear IPs. |
| Lenguaje | **GDScript** | Rapidez de desarrollo, suficiente para el alcance. |
| Avatar | **Mixamo → .glb** (ya consolidado) | Un único archivo con todas las animaciones. |
| Objetos CAD | **glTF/.glb** preferente, **.obj** fallback | Conserva color/material; compacto. |
| Empaquetado | Export Linux **con Embed PCK** (archivo único) | Distribución de un solo fichero. |

## 3. Estructura del proyecto

```
arquitecto-multiplayer/
├── project.godot
├── docs/
│   └── PLAN_IMPLEMENTACION.md        # este documento
├── net/
│   ├── network_manager.gd            # autoload: host/join, ENet
│   └── lan_discovery.gd              # autoload: broadcast/escucha UDP
├── Assets/
│   ├── male.glb                      # avatar Mixamo (ya entregado)
│   └── female.glb                    # avatar Mixamo (ya entregado)
├── characters/
│   ├── player.tscn                   # CharacterBody3D + cámara + sync
│   └── player.gd                     # input, movimiento, estados
├── levels/
│   ├── main_level.tscn               # escenario + spawns
│   └── cad_objects/                  # .glb/.obj importados de CAD
├── ui/
│   ├── lobby.tscn / lobby.gd         # menú: hospedar / lista de servidores
│   └── hud.tscn / hud.gd             # info en partida (jugadores, ping)
└── export_presets.cfg                # preset Linux x86_64
```

## 4. Arquitectura de red

### 4.1 Modelo
- **Listen-server**: el primer equipo pulsa "Hospedar" → es servidor **y** jugador
  (peer id 1, autoridad). El resto pulsa "Unirse" y elige el servidor de la lista.
- **Autoridad**: el servidor es la autoridad del estado del mundo. Cada jugador tiene
  autoridad sobre su propio input/movimiento (client-authority sencillo, válido para
  un uso colaborativo no competitivo de aula).

### 4.2 Descubrimiento en LAN (sin teclear IPs)
- El host emite un **broadcast UDP** periódico (p. ej. cada 1 s) en un puerto fijo de
  descubrimiento con: nombre de sala, IP, puerto de juego, nº de jugadores.
- Los clientes **escuchan** ese puerto y construyen una **lista de servidores** en el
  lobby. Al elegir uno, se conectan por ENet a su IP:puerto.
- Fallback manual: campo para introducir IP a mano por si el broadcast está filtrado.

### 4.3 Sincronización
- **`MultiplayerSpawner`**: instancia/elimina el avatar de cada jugador al
  conectar/desconectar.
- **`MultiplayerSynchronizer`** por jugador: replica posición, rotación y **estado de
  animación** (idle/walk/run/jump/crouch) a intervalos.
- **RPCs** para eventos puntuales (saltar, nombre del jugador, etc.).
- Interpolación en el cliente para suavizar el movimiento remoto.

### 4.4 Parámetros
- Puerto de juego (ENet) y puerto de descubrimiento (UDP) **fijos y documentados**
  (para que el profe pueda abrirlos en el firewall del aula si hiciera falta).
- Límite de jugadores: **6** por defecto (constante configurable).
- Controles (estilo "tanque", a confirmar): **`W`/`S`** adelante/atrás,
  **`A`/`D`** girar izquierda/derecha, **ratón** cámara, **Espacio** saltar,
  acción de **escalar** al acercarse a una zona escalable.

## 5. Pipelines de assets

### 5.1 Avatar (HECHO)
- Dos avatares entregados: **`Assets/male.glb`** y **`Assets/female.glb`**, cada uno
  consolidado desde Mixamo con **7 animaciones**:
  `idle · andar · andar_atrás · giro_izq · giro_der · saltar · escalar`.
- En Godot: el `.glb` aporta un `AnimationPlayer`; se monta un **`AnimationTree`** con
  un **AnimationNodeStateMachine**: estado de locomoción
  (idle ↔ andar ↔ andar_atrás ↔ giro_izq ↔ giro_der) + estados puntuales
  **saltar** y **escalar** (este último disparado al entrar en una zona escalable).
- El jugador **elige male/female** en el lobby; se replica a los demás vía red.
- *Pendiente al cablear*: confirmar los **nombres exactos de los clips** dentro de
  cada glb (deben coincidir entre male y female para reusar el `AnimationTree`).

### 5.2 Objetos CAD (recurrente)
- **Tinkercad**: exportar **GLTF (.glb)** (o OBJ). Evitar STL (sin color).
- **FreeCAD**: exportar **glTF**; OBJ como alternativa.
- **SketchUp**: glTF (extensión) / DAE / OBJ; la versión Free es limitada (STL/PNG).
- Mallas densas: **decimar** y/o regenerar colisiones simplificadas.
- En Godot: importar, asignar **colisión** (StaticBody3D, trimesh o convex según caso),
  escala y orientación coherentes.

## 6. Fases de implementación

> Cada fase termina en algo **ejecutable y probado**.

### Fase 0 — Setup + validación crítica en aula  ⚠️ primero
- Crear `project.godot` (renderer Compatibility), estructura de carpetas, repo git.
- Export Linux mínimo ("Hola mundo" que abre ventana).
- **Validar en UN equipo EducandOS**: que se puede dar **permiso de ejecución** y
  arranca. Confirmar **arquitectura** (x86_64) y rendimiento gráfico.
- *Entregable*: binario que abre ventana en un PC del aula. *Riesgo gate*: si no se
  puede ejecutar, replantear distribución antes de seguir.

### Fase 1 — Personaje single-player
- `player.tscn` (CharacterBody3D), cámara 3ª persona, input estilo tanque
  (W/S avanzar/retroceder, A/D girar, ratón cámara, Espacio saltar, escalar contextual).
- Integrar el `.glb` + `AnimationTree` (StateMachine) con las 7 animaciones.
- *Entregable*: te mueves por una sala vacía con animaciones correctas.

### Fase 2 — Escenario y objetos CAD
- `main_level.tscn` con suelo, iluminación y puntos de aparición (spawns).
- Importar 1–2 objetos CAD de prueba con colisión.
- *Entregable*: recorres el escenario y los objetos importados.

### Fase 3 — Multijugador LAN
- `NetworkManager` (host/join ENet) + `MultiplayerSpawner`/`Synchronizer`.
- Sincronizar posición + animación; RPCs de eventos.
- *Entregable*: dos instancias en la misma LAN se ven y se mueven en tiempo real.

### Fase 4 — Lobby + descubrimiento UDP
- `lan_discovery.gd` (broadcast/escucha) + UI de lista de servidores.
- Hospedar / unirse con un clic; fallback de IP manual; nombre de jugador.
- *Entregable*: flujo completo de aula sin teclear IPs.

### Fase 5 — Pulido + HUD
- HUD (jugadores conectados, ping, nombre), nombres flotantes sobre avatares,
  menú de pausa/salir, manejo de desconexiones.

### Fase 6 — Empaquetado y despliegue
- Export Linux x86_64 **con Embed PCK**; instrucciones de `chmod +x` / ejecución.
- Prueba final con **3+ equipos** del aula simultáneamente.
- *Entregable*: archivo único distribuible + mini-guía para el profe.

## 7. Riesgos y validaciones tempranas

| Riesgo | Mitigación |
|---|---|
| EducandOS bloquea el permiso de ejecución | **Probar en Fase 0**, antes de invertir trabajo. Alternativa: lanzar desde script/USB. |
| Hardware gráfico modesto | Renderer **Compatibility**, presupuesto de polígonos bajo, decimar CAD. |
| Firewall del aula filtra broadcast/ENet | Puertos fijos documentados + **fallback de IP manual**. |
| Nombres de clips distintos entre male/female | Verificar al cablear; renombrar para que coincidan y reusar un solo `AnimationTree`. |
| Mallas CAD pesadas/sin colisión usable | Decimar + colisiones simplificadas en import. |

## 8. Pruebas
- **Local**: dos instancias en el PC de desarrollo (una host, una cliente) para iterar.
- **LAN real**: 2 → 3 → N equipos del aula.
- Checklist por release: arranca, descubre servidor, conecta, se sincroniza
  movimiento/animación, soporta desconexión limpia.

## 9. Despliegue en el aula
1. Exportar binario Linux (Embed PCK).
2. Copiar a cada equipo (USB / carpeta de red).
3. `chmod +x arquitecto` (o "Permitir ejecución" en propiedades).
4. Un equipo "Hospedar"; los demás "Unirse" → elegir de la lista.

## 10. Backlog / mejoras futuras
- Carga dinámica de nuevos objetos CAD sin recompilar (carpeta escaneada al inicio).
- Selección entre varios avatares.
- Modo "guía" (un usuario mueve la cámara de todos).
- Notas/etiquetas sobre los objetos.
- Export adicional a Windows para pruebas en casa.

---

### Decisiones confirmadas (2026-06-01)
- [x] Arquitectura de los equipos: **x86_64**.
- [x] Permiso de ejecución en EducandOS: **sí disponible**.
- [x] Avatares: **`Assets/male.glb`** y **`Assets/female.glb`** (selección en lobby).
- [x] Nº máximo de jugadores: **6** (configurable).
- [x] Controles: **teclado + ratón, WASD** (sin gamepad de momento).

### Pendientes (al cablear)
- [ ] Nombres exactos de los clips de animación dentro de cada `.glb`.
