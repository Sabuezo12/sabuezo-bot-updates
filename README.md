# Sabuezo Bot - MythicOT

Version actual: **3.0.25**. Actualizaciones publicas mediante GitHub, sin contrasenas.

## Instalacion

Ejecuta este script en el editor de scripts del bot:

```lua
modules.corelib.HTTP.get('https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/bootstrap.lua', function(script, err) if err or not script then warn('No se pudo descargar Sabuezo') return end assert(loadstring(script))() end)
```

El instalador descarga el paquete completo antes de reemplazar archivos, valida el tamano de cada descarga y coloca el Loader al final. Al terminar, recarga el bot. Los archivos anteriores se respaldan en `bot/<config>/_updates/bootstrap_3.0.25/`. Los perfiles y las configuraciones guardadas de cada usuario se conservan.

## Actualizaciones

El panel **Updater** aparece en **Main**. **Check** consulta GitHub y **Update** instala los archivos pendientes. Se conserva la actualizacion automatica al entrar si esta activada en los ajustes existentes. El bot se recarga automaticamente al terminar una instalacion, tambien al pulsar Update.

Los archivos del manifest apuntan a la etiqueta `v3.0.25`, para que una descarga use una sola version del bot. La antigua version de cierre 3.0.17 esta bloqueada y su payload fue retirado de la version actual del repositorio.

## Contenido publicado

Se publican los scripts Lua, interfaces OTUI, imagenes y textos de licencia necesarios para el bot. Se conservan los scripts de la version anterior y se incorporan las mejoras de BotServer, Player List y exiva probadas en pruebas.

Quedan fuera los perfiles de `storage/`, configuraciones de HealBot/AttackBot/Supplies, listas de jugadores, teclas del editor, rutas de CaveBot, configuraciones de TargetBot, distribucion de paneles, tokens, contrasenas y respaldos. No se publica ni se importa una plantilla personal de Sabuezo.

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
