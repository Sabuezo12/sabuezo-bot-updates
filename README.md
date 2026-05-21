# sabuezo-bot-updates

Repositorio de actualizaciones para el bot de Sabuezo.

## Instalacion inicial

En el editor de scripts del bot, ejecuta:

```lua
modules.corelib.HTTP.get('https://raw.githubusercontent.com/Sabuezo12/sabuezo-bot-updates/main/bootstrap.lua', function(script) assert(loadstring(script))() end)
```

Cuando termine, reinicia el cliente o recarga el bot. Despues aparecera un panel llamado `Updater` en `Main`.

## Actualizaciones normales

1. Abre el panel `Updater`.
2. Presiona `Check`.
3. Si hay nueva version, presiona `Update`.
4. Reinicia el cliente o recarga el bot.

El updater hace backup de los archivos reemplazados dentro de:

```text
bot/<config>/_updates/
```

## No se publican

Este repo no debe incluir perfiles ni rutas privadas:

```text
storage/
vBot_configs/
cavebot_configs/
targetbot_configs/
_archive/
```
