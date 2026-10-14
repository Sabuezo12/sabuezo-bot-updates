RinoBot 3.1.0: actualización completa con migración de perfiles.

La prueba sobre una copia clásica dentro de MythicOT ya fue confirmada. El paquete está preparado para probarlo con uno o dos compañeros; el canal público clásico continúa en 3.0.28.

Incluye la interfaz RinoBot, Modo clásico, perfiles por personaje, Scripts integrados, Iconos, apariencia y todos los módulos actuales de CaveBot, TargetBot y Navi. Se distribuyen 296 archivos oficiales. No contiene perfiles personales, rutas, guilds, listas de amigos ni scripts privados de Alfonso.

Para probarlo con un compañero:

1. Extrae el ZIP completo, manteniendo juntas las carpetas y los dos archivos del instalador.
2. Cierra MythicOT. Usa una copia de su carpeta clásica para la primera prueba; debe contener `_Loader.lua` y sus carpetas de configuración.
3. Desde PowerShell, situado en la carpeta extraída, revisa primero el plan:

```powershell
.\Install-RinoBot.ps1 -BotDirectory 'C:\ruta\a\la\copia\del\bot' -WhatIf
```

4. Instala sobre esa misma copia:

```powershell
.\Install-RinoBot.ps1 -BotDirectory 'C:\ruta\a\la\copia\del\bot'
```

5. Abre el cliente y elige esa copia. Con CaveBot y TargetBot apagados, comprueba perfiles, heals, supplies, rutas y scripts; cambia de perfil y recarga. El perfil numérico activo se convierte en el perfil del personaje. Los otros perfiles ocupados aparecen como «Perfil clasico N» y pueden asociarse a su personaje al conectarlo por primera vez. Los perfiles nuevos usan los ajustes predeterminados; los importados mantienen los suyos.

Los originales numéricos permanecen en sus carpetas. Se importan hasta los diez slots del cliente. La migración se ejecuta antes de crear el primer índice de perfiles con nombre; un índice Helper existente conserva sus perfiles y no vuelve a importar el caché numérico.

El instalador verifica los archivos antes de reemplazarlos, conserva un respaldo íntegro y escribe un registro de recuperación. El updater descarga todo el paquete y comprueba su SHA-256 antes de instalar. Si encuentra código personalizado que no reconoce, detiene la actualización indicando el archivo. Esos cambios deben revisarse; no hay una opción de sobrescritura forzada.

El instalador clásico reconocido que esté guardado en Scripts conserva su texto y su estado ON/OFF, pero RinoBot omite su ejecución para evitar que reinstale el código antiguo. Los scripts personales ordinarios conservan su ejecución. Durante la prueba previa a publicar el bootstrap nuevo, desactiva temporalmente un script personalizado que combine el instalador antiguo con otras funciones; ese código requiere revisión por separado.

Los respaldos están en `_updates/transactions/tN/backup/`, con `backup-index.json` y `journal.json`. La instalación queda pendiente de validar hasta que RinoBot abre correctamente. Ante una instalación o arranque fallidos, el cargador puede recuperar el código anterior. La restauración automática conserva los datos personales; no deshace ajustes realizados después.

Para restaurar manualmente el código desde el último respaldo, con el cliente cerrado:

```powershell
.\Install-RinoBot.ps1 -BotDirectory 'C:\ruta\al\bot' -Mode Restore
```

Para recuperar además los ajustes de aquella copia del respaldo:

```powershell
.\Install-RinoBot.ps1 -BotDirectory 'C:\ruta\al\bot' -Mode Restore -RestoreSettings
```

La restauración verifica el respaldo y guarda el estado reciente en `_updates/rescue-*`. Conserva las cadenas antiguas que no son UTF-8. Si detecta cambios de código posteriores, solicita revisar ese archivo antes de restaurar.

Tras confirmar la prueba con los compañeros, la publicación tiene dos etapas:

1. Subir `publish/bootstrap.lua`, `publish/releases/3.1.0`, `publish/releases/3.0.29` y `publish/rinobot/manifest.json` al repositorio de updates. El bootstrap nuevo evita competir con el updater puente. Verificar los hashes de los archivos descargados. Los directorios versionados deben conservarse sin modificar.
2. Como último paso, publicar `publish/manifest-bridge-to-publish-last.json` con el nombre `manifest.json` en la raíz del repositorio. Es el cambio que empieza la distribución a todos: instala primero el updater puente 3.0.29 y después permite descargar RinoBot 3.1.0.

El puente está preparado para la base clásica publicada 3.0.28. Su manifest conserva los 283 archivos de esa base, fijados a v3.0.28, e incorpora el updater puente: un cliente 3.0.28 cambia únicamente Updater; una instalación nueva también obtiene la base completa para poder arrancar. Las instalaciones anteriores deben actualizarse a esa base o revisarse con el instalador antes de distribuir el puente. El nuevo updater conserva la preferencia de actualización automática. No se cambia el nombre físico de la carpeta del bot.

La copia privada «RinoBot-Piloto» de Alfonso tiene `_updates/pilot.marker`, que desactiva las descargas públicas en esa copia. Este marcador no forma parte del paquete para compañeros.

Las pruebas cubren la instalación, migración y recuperación. El funcionamiento específico de una ruta, una rotación o un servidor debe comprobarse en la prueba de cada compañero.
