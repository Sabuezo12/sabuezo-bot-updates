# Sabuezo Bot - MythicOT

Version preparada: **3.0.18**. Actualizaciones publicas mediante GitHub, sin contrasenas.

## Instalacion

Ejecuta este script en el editor de scripts del bot:

```lua
modules.corelib.HTTP.get('https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/bootstrap.lua', function(script, err) if err or not script then warn('No se pudo descargar Sabuezo') return end assert(loadstring(script))() end)
```

El instalador descarga el paquete completo antes de reemplazar archivos, valida el tamano de cada descarga y coloca el Loader al final. Al terminar, recarga el bot. Los archivos anteriores se respaldan en `bot/<config>/_updates/bootstrap_3.0.18/`. Los perfiles y las configuraciones guardadas de cada usuario se conservan.

## Actualizaciones

El panel **Updater** aparece en **Main**. **Check** consulta GitHub y **Update** instala los archivos pendientes. Se conserva la actualizacion automatica al entrar si esta activada en los ajustes existentes.

Los archivos del manifest apuntan a la etiqueta `v3.0.18`, para que una descarga use una sola version del bot. La antigua version de cierre 3.0.17 esta bloqueada y su payload fue retirado de la version actual del repositorio.

## Contenido publicado

Se publican unicamente los scripts Lua, interfaces OTUI e imagenes necesarias para el bot. Los scripts proceden de la carpeta Sabuezo2 usada en MythicOT.

Quedan fuera los perfiles de `storage/`, configuraciones de HealBot/AttackBot/Supplies, listas de jugadores, teclas del editor, rutas de CaveBot, configuraciones de TargetBot, distribucion de paneles, tokens, contrasenas y respaldos. No se publica ni se importa una plantilla personal de Sabuezo.

## Cambios incluidos

- Conditions: haste al moverse, recuperacion fuera de PZ y de combate.
- Monk/exalted monk con etiqueta MK y soporte de Friend Healer.
- Deteccion de guild desde look y nuevos IDs de magic wall en el timer.
- Ocultar mascotas, manteniendo las auras.
- Auto bless mediante datos del cliente y contador de municion.
- Inmortal, sus contadores SSA/MR/MSP, ajustes de equipo y HUD.
- ContainerManager restaurado a la version anterior a las correcciones de Slow macro.

Las opciones y scripts que cada usuario haya creado en su editor se conservan. La version de ContainerManager publicada es la restaurada antes de las correcciones de Slow macro.
