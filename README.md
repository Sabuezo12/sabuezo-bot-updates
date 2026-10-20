# RinoBot - MythicOT

Versión estable: **3.1.9**. [Notas de la actualización](https://github.com/Sabuezo12/sabuezo-bot-updates/releases/tag/v3.1.9). Puente clásico: **3.0.31**.

## Actualización

Recarga el bot o espera su comprobación automática cada cinco minutos. Conserva perfiles, rutas, scripts, heals y supplies; después de instalar y verificar vuelve a Helper. Puedes elegir clásico manualmente hasta la siguiente actualización. Se respetan development.lock, recuperación de versiones fallidas y protección contra downgrades.

Versiones antiguas con Auto OFF necesitan adoptar el nuevo updater una primera vez desde su panel. Si no hay Updater, usa la instalación inicial.

## Cambios de 3.1.9

- Push Max y Huida priorizan la limpieza bajo el jugador; no gastan Disintegrate en objetos de un destino caminable.
- Container Manager vuelve a abrir la siguiente BP anidada de Arrows al vaciarse la actual, incluso del mismo tipo.
- Inicio muestra el balance de niveles de la sesion y lo conserva al recargar.
- El cambio local de WASD queda descartado: CaveBot conserva el movimiento publicado en 3.1.8.

335 archivos oficiales, 136 Lua compilados y 94,621 comprobaciones locales simuladas/estaticas; 60 origenes de migracion completos. Configuraciones propias conservadas; confirmacion reciente en MythicOT pendiente. [Notas completas](rinobot/3.1.9-notas.md) e [informe de validacion](rinobot/3.1.9-validacion.json).

## Cambios de 3.1.8

- Push Max de Sabuezo incorporado: PUSH/DEST, Fire Field distante, Disintegrate melee, Destroy Field, recuperacion y cierre MW.
- Pociones y objetos coordinados, curacion urgente prioritaria y spells libres.
- Huida sin BugMap ni Fire Field; cruza fields, rompe bloqueos y recupera movimiento. ZonaPZ espera solo tras huida y permite reiniciar su contador.
- AntiPush se puede desactivar al tercer paso; Friend Healer excluye enemigos/atacantes y evita curar jugadores ajenos con Mas Res.
- Aeron Knight permanece intacto. No incluye una supuesta solucion de RAM.

335 archivos oficiales, 136 Lua compilados y 84,422 comprobaciones simuladas/estaticas. Instalacion completa desde 53 origenes, con datos propios conservados. Novedades recientes pendientes de confirmar en MythicOT. [Notas completas](rinobot/3.1.8-notas.md) e [informe de validacion](rinobot/3.1.8-validacion.json).

## Cambios de 3.1.7

- CaveBot incorpora ZonaPZ como destino de Huida PvP; Wait Stamina recupera minima/maxima y ramas por label.
- Push Max normal elige Destroy Field o Disintegrate segun el obstaculo y confirma la limpieza, conservando sus tiempos.
- AntiPush usa !withdraw 2000 fijo, prepara cambio y reserva gold/platinum; Gold Converter tiene ON/OFF propio y se pausa durante AntiPush.
- Spy Level incorpora icono: clic izquierdo para subir y derecho para bajar.
- El Push Max experimental de Aeron Knight sigue fuera. No incluye una supuesta correccion de RAM.

334 archivos oficiales, 135 fuentes Lua compiladas y 48,789 comprobaciones locales simuladas/estaticas. Migracion completa desde 29 origenes. Conserva datos propios y las mejoras de 3.1.6. Novedades recientes pendientes de confirmar en MythicOT. [Notas completas](rinobot/3.1.7-notas.md) e [informe de validacion](rinobot/3.1.7-validacion.json).

## Cambios de 3.1.6

- Timer Executor con filtros combinables y condiciones en dos columnas; Dummy Smart con listas de alternativas y ajustes compactos.
- Perfiles con catálogos propios por personaje y valores iniciales por vocación; HealBot con uso desde inventario/purse cuando el cliente lo admite.
- AttackBot con correcciones de carga y planificación al vencer cooldowns nativos; conserva requisitos y exhaust.
- Huida PvP integrada y activada por defecto en nuevas configuraciones, Wait Stamina obligatorio y correcciones de Dynamic Lure.
- Container Manager con recuperación del destino cerrado y conservación de Main ante eventos ajenos de quiver/purse.
- **Fuera el Push Max experimental de Aeron Knight.** El motor y los tiempos publicados se conservan, con las pausas estables de Huida PvP.

334 archivos oficiales, 135 fuentes Lua compiladas y 44.161 comprobaciones locales simuladas/estáticas. Migración completa desde 26 orígenes. No se incluyen datos personales. Aspecto y comportamiento recientes pendientes de confirmar en MythicOT. [Notas completas](rinobot/3.1.6-notas.md) e [informe de validación](rinobot/3.1.6-validacion.json).

## Cambios de 3.1.5

- AttackBot: criterio de daño estimado por turno para las cinco vocaciones entre ataques listos; sin bloqueos compartidos ficticios sobre cooldowns nativos. Respeta condiciones, seguridad y Harmony.
- Arrastra la runa para seleccionar su ID; conserva Aplicar/Descartar y Quitar.
- CaveBot: interruptor en cabecera; activar guarda y apaga la grabación. Clic derecho abre ruta y waypoints.
- Versión coherente entre perfiles y consola general en Ajustes con distribución corregida.
- **Push Max conserva exactamente 3.1.4. Las mejoras experimentales de Push Max y su coordinador quedan fuera.**

328 archivos oficiales, 130 fuentes Lua compiladas y 33.536 comprobaciones locales simuladas/estáticas; pruebas nativas recientes pendientes. [Notas completas](rinobot/3.1.5-notas.md) e [informe de validación](rinobot/3.1.5-validacion.json). No se distribuyen datos personales. [Versión anterior 3.1.4](https://github.com/Sabuezo12/sabuezo-bot-updates/releases/tag/v3.1.4).

## Instalación inicial

En el editor de scripts del bot ejecuta:

```lua
modules.corelib.HTTP.get('https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/bootstrap.lua', function(script, err) if err or not script then warn('No se pudo descargar Sabuezo') return end assert(loadstring(script))() end)
```

El bootstrap instala el puente clásico 3.0.31. Recarga el bot para que su updater descubra e instale RinoBot 3.1.9. Se conservan bootstrap, puente y publicaciones anteriores.

## Historial clásico

## Cambios de 3.0.28

- Updater By: Sabuezo estrena una ventana compacta con el estilo de Navi, cierre con X y acceso con estado y version desde Main.
- Las pestanas Novedades, Historial y Detalles muestran las notas de la version, todas las versiones publicadas y los archivos pendientes reales.
- Se muestran las versiones instalada y disponible, el avance por archivos y las fases de descarga, instalacion y recarga.
- Se corrige el interruptor ON/OFF de Actualizar al entrar para mostrar completos el circulo y el texto al activar, desactivar o bloquear el control.
- Los controles se bloquean mientras se comprueba o instala una actualizacion; se evitan solicitudes duplicadas y se puede reintentar despues de un error.
- Se conservan la preferencia de actualizacion automatica, los perfiles y las configuraciones personales; el bot se recarga automaticamente al terminar una instalacion completa.
- El paquete incluye todas las mejoras publicadas de Navi y exiva, incluido el mapa independiente, el fondo negro, Punto exiva, los avistamientos exactos y las referencias aproximadas.

Para instalar 3.0.28 desde el Updater anterior, pulsa Check y Update. En el nuevo Updater usa Buscar actualizacion y Actualizar. El bot se recarga al terminar y conserva las configuraciones personales.

## Cambios de 3.0.27

- Navi cambia al nuevo objetivo buscado por el iniciador que estas viendo; retira el punto anterior mientras espera sus respuestas y mantiene separadas las coordenadas de cada jugador.
- Las respuestas muy lejos aportan un punto amarillo de acercamiento compatible con las lecturas disponibles, identificado como orientativo y con la distancia del objetivo sin confirmar.
- Punto exiva permite centrar Navi en esa referencia; una estimacion con distancia o un avistamiento actual la sustituye cuando llega informacion mas precisa.
- Se conserva una estimacion vigente del mismo jugador entre rondas mientras llegan nuevas respuestas, sin renovar su caducidad ni reutilizar mediciones canceladas.
- Las estimaciones de piso incierto se muestran sobre un piso permitido de la vista; los avistamientos confirmados conservan su piso real.
- El minimapa de Navi usa fondo negro y una flecha de rumbo cuando el punto queda fuera de la vista; las guias se ocultan al terminar, cancelar o cerrar el mapa.
- El mapa del cliente conserva su camara independiente; se mantiene la seleccion sin tope fijo de observadores, el filtro de redundancia por pantalla y la recarga automatica al actualizar.

Instala 3.0.27 desde Updater: Check y Update. El bot se recarga automaticamente al terminar y conserva las configuraciones personales. En Navi, Punto exiva centra el mapa en la estimacion o referencia de acercamiento disponible.

## Cambios de 3.0.26

- Se elimina el limite fijo de tres observadores: todos los miembros disponibles con tracker y posicion reciente pueden responder a la ronda.
- La redundancia se filtra por vision real del iniciador: los companeros que aparecen en su pantalla no dicen exiva para esa ronda; se retira la exclusión por distancia minima entre observadores.
- La rediscovery incorpora companeros tardios sin repetir hechizos de quienes ya respondieron; se mantienen los controles de cancelacion, caducidad, pausa y cooldown.
- Se agrega Punto exiva junto a Mini mapa para abrir Navi centrado en la posicion aproximada, exacta o ultima vista del objetivo, con los marcadores del grupo y nombres al pasar el mouse.
- La vista del objetivo conserva las distancias medidas desde el iniciador; Centrar mapa vuelve a su perspectiva y el minimapa del cliente sigue independiente.
- El boton Punto exiva se desactiva cuando no hay un punto vigente o solo hay rumbo sin distancia; se mantiene la limpieza de marcadores al parar o terminar la busqueda.
- Se conserva la recarga automatica al terminar la actualizacion y las configuraciones personales.

Instala 3.0.26 desde Updater: Check y Update. El bot se recarga automaticamente al terminar. Para iniciar rondas sin tope, el personaje que inicia debe usar esta version; se recomienda actualizar a todos los miembros.

## Cambios de 3.0.25

- BotServer se presenta como Navi By: Sabuezo; se corrige la X de cierre, se retira el boton Cerrar y se ajustan iconos y el interruptor ON/OFF.
- El minimapa opcional de Navi se despliega hacia abajo con una vista ampliada y controles de zoom; su camara, piso y zoom son independientes del minimapa del cliente.
- Navi muestra companeros y objetivo de exiva con marcadores diferenciados y nombres al pasar el mouse; la vista de exiva usa la perspectiva del iniciador.
- El mapa muestra distancia en casillas a companeros y objetivo, distingue posiciones aproximadas, exactas y ultimas vistas, y conserva una guia punteada limitada.
- Se evita que respuestas automaticas y callbacks duplicados inicien nuevas cadenas de exiva o cambien el objetivo personal de Exiva Last.
- Apagar la automatizacion del iniciador cancela su ronda y los exivas pendientes; una respuesta en vuelo no reactiva una busqueda apagada.
- Se rechazan solicitudes caducadas o fuera de orden, se respetan los tiempos de hechizos y se da mas margen para descubrir companeros con una conexion lenta.
- Se mantienen hasta tres observadores separados por ronda y la prioridad de la posicion exacta cuando cualquier companero ve al objetivo.
- En Exivas, el tooltip de Iniciador muestra el origen de la busqueda, seleccionados, respuestas recibidas y el motivo de espera del personaje local.
- Se conservan HP y mana compartidos, favoritos, alertas, parada de lider, perfiles personales y recarga automatica al terminar el update.

Todos los miembros deben instalar 3.0.25 para recibir la nueva cancelacion de rondas y las correcciones de exiva. En Updater, pulsa Check y Update; el bot se recarga al finalizar. El mapa de Navi sigue siendo opcional.

## Cambios de 3.0.24

- BotServer estrena una interfaz compacta de 540 x 460 con pestanas Companeros, Exivas y Conexion, marcos e iconos propios.
- La lista muestra HP, mana y piso; permite buscar, marcar favoritos, filtrar el mismo piso, ordenar y ubicar a cada companero en el mapa.
- Se comparte HP junto con mana y posicion. Si un companero usa un bot anterior y esta en tu pantalla, se lee su HP visible sin conservar criaturas ni valores al perderlo de vista.
- El tooltip del boton BotServer muestra los nombres de los conectados. Se retiran los tiempos hace X s de las filas.
- El companero seleccionado permite centrar el mapa y activar una vista pequena opcional, desactivada inicialmente.
- Alertas plegables de HP y mana, con umbrales configurables y sonido opcional. Alertas y sonido empiezan desactivados.
- La pestana Exivas conserva el objetivo, el iniciador, la posicion y la actividad reciente; Parar exivas sigue reservado a los lideres.
- Se conserva la recarga automatica al terminar la actualizacion y las configuraciones personales de cada usuario.

Para ver HP a distancia, los companeros deben instalar esta version y conectarse al mismo BotServer. La lectura local funciona solo mientras el companero esta visible; no sustituye el envio de HP desde su bot.

## Cambios de 3.0.23

- BotServer muestra el iniciador, el objetivo y la repeticion de las busquedas en Exivas recientes.
- Parar exivas detiene las automatizaciones del grupo durante 60 segundos. Disponible para Rod Master, Sabuezo y Aeron Knight.
- Si cualquier companero ve al objetivo, comparte su posicion exacta; al perderlo de vista se identifica la ultima posicion vista.
- El minimapa conserva el punto y la guia punteada. Se retiran los recuadros amarillos y las etiquetas permanentes; el cursor muestra solo nombre y posicion.
- La estimacion usa hasta tres observadores separados, favorece distintos angulos y utiliza lecturas recientes segun la hora del lanzamiento.
- Se reducen exivas duplicados y lanzamientos mientras hay vision confirmada; se conserva la limpieza segura y la pausa del dibujo al mover el mapa ampliado.
- Se mantiene la recarga automatica del bot al terminar de instalar el update.

Para compartir vision y obedecer Parar exivas, los companeros deben instalar esta version y conectarse al mismo BotServer. El bloqueo de 60 segundos controla las automatizaciones del bot. La guia muestra un rumbo directo; la estimacion a distancia depende de los rangos del servidor.

## Cambios de 3.0.22

- El bot se recarga automaticamente al terminar de instalar una actualizacion, tanto manual como automatica.
- La recarga espera a que terminen las descargas y se guarden los archivos, la version y los hashes; se programa una sola vez.
- Revisar updates, tener la ultima version o recibir un error de descarga o escritura no provoca una recarga.

Si esta version se instala manualmente usando el Updater anterior, puede requerir una recarga manual para activar este cambio. Las siguientes actualizaciones ya se recargan automaticamente.

## Cambios de 3.0.21

- BotServer elimina el intercambio de vocaciones y magic walls; conserva presencia, mana, mensajes y exiva compartido.
- Player List incorpora el outfit por vocacion, desactivado por defecto e independiente de los colores.
- Los companeros se distinguen con un diamante celeste y el objetivo de exiva con una referencia amarilla y su zona aproximada.
- La guia de exiva muestra puntos y flechas hacia la referencia, con indicaciones cuando queda fuera del mapa o en otro piso.
- Se reduce el trabajo de dibujo al mover el mapa; Mapa grande fluido limita las actualizaciones de arrastre y permite desactivarlo en Bot Settings.
- Se corrigen los accesos a widgets destruidos y la limpieza de lineas y marcadores al terminar una busqueda, cerrar mapas o recargar el bot.
- Las respuestas automaticas ya no inician nuevas cadenas de exiva; las solicitudes cerradas y las respuestas tardias se descartan.
- El punto de referencia se conserva mientras las lecturas actuales lo permiten; una sesion anterior no reemplaza la estimacion mas reciente del mismo jugador.
- La referencia y la guia muestran Inicio: nombre para identificar quien inicio el exiva compartido.
- La actualizacion conserva perfiles, rutas, hotkeys, listas y configuracion personal.

La guia indica una referencia aproximada, sin calcular una ruta transitable. Las correcciones anteriores de mapas fueron confirmadas en juego por el usuario; la estabilidad del punto y la etiqueta del iniciador se verificaron con pruebas simuladas.

## Cambios de 3.0.20

- Inmortal guarda el equipo saliente en la BP principal y espera la confirmacion antes de equipar la proteccion; evita el intercambio fallido con una BP llena de Might Rings.
- Might Rings y SSA se conservan hasta consumirse; el equipo normal vuelve cuando terminan las condiciones de peligro y se cumple la recuperacion configurada.
- Energy Ring conserva sus porcentajes de encendido y apagado; si interrumpe un Might Ring, se vuelve a equipar un Might Ring antes de regresar al normal.
- Inmortal tambien puede abastecerse de Might Rings y SSA desde la Loot Pouch del purse, abriendo esa rama cuando el acceso por ID no encuentra el equipo.
- Utamo Vita y Exana Vita usan cooldowns individuales y grupales del cliente. Exana no espera el cooldown individual de Utamo y los intentos rechazados no generan una espera falsa de catorce segundos.
- Se conserva el contador de consumo y el HUD; los movimientos de equipo propios no se cuentan como items gastados.

La BP principal necesita espacio para guardar el equipo saliente. Inmortal se verifico con 210 comprobaciones simuladas; falta confirmar el comportamiento dentro del juego.

## Cambios incluidos

- AttackBot: interfaz compacta con iconos reales, seleccion automatica o prioridad por orden, seguridad y ajustes avanzados.
- Rotaciones por vocacion para Paladin, Druid, Sorcerer, Knight y Monk, con cooldowns del cliente y exhaust de MythicOT.
- Preparacion del siguiente wave o beam, mejor area de impacto, giro, reposicionamiento y coordinacion con Face Monster.
- Cantidades exactas de monstruos y UEs de Druid con cooldowns independientes y exhaust grupal de cuatro segundos.
- TargetBot: editor compacto en una pantalla, seguimiento a la distancia configurada, prioridad a pasos rectos y proteccion contra escaleras.
- Anchoring con centro fijo y radio estricto para Keep Distance, antitrap y BugMap; compatible con los limites de Dynamic Lure.
- AttackBot controla spells y runas al estar encendido; TargetBot mantiene objetivos, ataque normal, movimiento y loot.
- AutoBless tras entrar o revivir, reconocimiento de la respuesta del servidor y reintentos ante informacion vieja del cliente.
- Mejoras acumuladas de Imbuements, ContainerManager, supplies y aceptacion automatica de muerte.
- Conditions: haste al moverse, recuperacion fuera de PZ y de combate.
- Monk/exalted monk con etiqueta MK y soporte de Friend Healer.
- Deteccion de guild desde look y nuevos IDs de magic wall en el timer.
- Ocultar mascotas, manteniendo las auras.
- Auto bless mediante datos del cliente y contador de municion.
- Inmortal, sus contadores SSA/MR/MSP, ajustes de equipo y HUD.
- ContainerManager restaurado a la version anterior a las correcciones de Slow macro.

Las opciones y scripts que cada usuario haya creado en su editor se conservan. La version de ContainerManager publicada es la restaurada antes de las correcciones de Slow macro.

La sintaxis, el manifest y la coordinacion de los bots se verifican con pruebas simuladas. El comportamiento real de movimiento y compra de bless depende del cliente y servidor; requiere comprobacion durante el juego.
