[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)][string]$BotDirectory,
  [ValidateSet('Install','Restore')][string]$Mode='Install',
  [string]$ReleaseDirectory,
  [string]$BackupDirectory,
  [switch]$RestoreSettings
)
$ErrorActionPreference='Stop'
$rinoScriptPath=$MyInvocation.MyCommand.Path
$rinoScriptDirectory=Split-Path -Parent $rinoScriptPath
if (-not $ReleaseDirectory) { $ReleaseDirectory=Join-Path $rinoScriptDirectory 'full' }
$rinoRoot=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $BotDirectory).Path).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $rinoRoot '_Loader.lua') -PathType Leaf)) { throw 'Selecciona la carpeta de un bot existente, que contenga _Loader.lua.' }
if ((Get-Item -LiteralPath $rinoRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'La carpeta no puede ser un enlace.' }
function Get-RinoPath([string]$Root,[string]$Relative) {
  if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative.Contains('..') -or $Relative.Contains(':') -or $Relative.StartsWith('/') -or $Relative.StartsWith('\')) { throw "Ruta insegura: $Relative" }
  $rinoTarget=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
  if (-not $rinoTarget.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'La ruta sale de la carpeta seleccionada.' }
  $rinoParent=Split-Path -Parent $rinoTarget
  while ($rinoParent.StartsWith($Root,[StringComparison]::OrdinalIgnoreCase)) {
    if ((Test-Path -LiteralPath $rinoParent) -and ((Get-Item -LiteralPath $rinoParent).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'La ruta contiene un enlace.' }
    if ($rinoParent -eq $Root) { break }
    $rinoParent=Split-Path -Parent $rinoParent
  }
  return $rinoTarget
}
function Get-RinoHash([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $rinoHashEngine=[Security.Cryptography.SHA256]::Create()
  $rinoStream=[IO.File]::OpenRead($Path)
  try { return [BitConverter]::ToString($rinoHashEngine.ComputeHash($rinoStream)).Replace('-','').ToLowerInvariant() }
  finally { $rinoStream.Dispose();$rinoHashEngine.Dispose() }
}
function Test-RinoCode([string]$Path) {
  if ($Path -eq '_Loader.lua' -or $Path -eq 'dummy.lua') { return $true }
  return $Path -cmatch '^(vBot|cavebot|targetbot|zFreeScripts|zPaidScripts)/' -and
    ($Path -cmatch '\.(lua|otui|ui|png|otfont|txt)$' -or $Path -eq 'vBot/HelperProfileDefaults.json') -and
    $Path -notmatch '(^|/)(storage|profiles|_helper_profiles|vBot_configs|cavebot_configs|targetbot_configs|_[^/]*)(/|$)'
}
function Write-RinoBytes([string]$Path,[byte[]]$Bytes) {
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
  [IO.File]::WriteAllBytes($Path,$Bytes)
  $rinoRead=[IO.File]::ReadAllBytes($Path)
  $rinoSha=[Security.Cryptography.SHA256]::Create()
  try {
    $rinoExpected=[BitConverter]::ToString($rinoSha.ComputeHash($Bytes))
    $rinoActual=[BitConverter]::ToString($rinoSha.ComputeHash($rinoRead))
    if ($rinoActual -ne $rinoExpected) { throw 'No se pudo verificar una escritura.' }
  } finally { $rinoSha.Dispose() }
}
function Write-RinoJson([string]$Path,$Value) {
  $rinoText=ConvertTo-Json -InputObject $Value -Depth 100
  Write-RinoBytes $Path ([Text.Encoding]::UTF8.GetBytes($rinoText))
}
function Read-RinoSettings([string]$Path) {
  # Older clients can save raw legacy bytes in JSON strings. Do not rewrite
  # those files through PowerShell's Unicode conversion; Lua preserves them.
  $rinoUtf8=New-Object Text.UTF8Encoding($false,$true)
  try { $rinoJson=$rinoUtf8.GetString([IO.File]::ReadAllBytes($Path)) }
  catch { return $null }
  if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('AsHashtable')) {
    return ConvertFrom-Json -InputObject $rinoJson -AsHashtable
  }
  Add-Type -AssemblyName System.Web.Extensions
  $rinoSerializer=New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $rinoSerializer.MaxJsonLength=[int]::MaxValue
  $rinoSerializer.RecursionLimit=4096
  return $rinoSerializer.DeserializeObject($rinoJson)
}
function Save-RinoSnapshot([string]$Destination) {
  $rinoFiles=@(Get-ChildItem -LiteralPath $rinoRoot -File -Recurse -Force)
  $rinoIndex=@()
  foreach ($rinoFile in $rinoFiles) {
    $rinoRel=$rinoFile.FullName.Substring($rinoRoot.Length+1).Replace('\','/')
    if ($rinoRel -match '^(_updates|_helper_dev|_archive|Sabuezo2)/') { continue }
    if ($rinoFile.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'El respaldo contiene un enlace.' }
    $rinoSource=Get-RinoPath $rinoRoot $rinoRel
    $rinoCopy=Get-RinoPath $Destination ('backup/'+$rinoRel)
    Write-RinoBytes $rinoCopy ([IO.File]::ReadAllBytes($rinoSource))
    $rinoHash=Get-RinoHash $rinoSource
    if ((Get-RinoHash $rinoCopy) -ne $rinoHash) { throw "Respaldo incorrecto: $rinoRel" }
    $rinoIndex+=@{path=$rinoRel;sha256=$rinoHash;size=$rinoFile.Length}
  }
  Write-RinoJson (Join-Path $Destination 'backup-index.json') @($rinoIndex)
  return ,$rinoIndex
}
if (-not $WhatIfPreference -and (Split-Path -Leaf (Split-Path -Parent $rinoRoot)) -eq 'bot' -and @(Get-Process -Name MythicOTC -ErrorAction SilentlyContinue).Count -gt 0) {
  throw 'Cierra MythicOT antes de instalar o restaurar archivos. Puedes usar -WhatIf para revisar el plan.'
}
$rinoPending=Join-Path $rinoRoot '_updates/pending.json'
if ($Mode -eq 'Restore') {
  if (-not $BackupDirectory) {
    $rinoJournal=Get-Content -LiteralPath $rinoPending -Raw -Encoding UTF8 | ConvertFrom-Json
    $BackupDirectory=Join-Path $rinoRoot ('_updates/transactions/'+($rinoJournal.path -split '/')[-1])
  }
  $rinoBackup=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $BackupDirectory).Path).TrimEnd('\')
  $rinoTransactions=Join-Path $rinoRoot '_updates/transactions'
  if (-not $rinoBackup.StartsWith($rinoTransactions+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'El respaldo debe pertenecer al bot seleccionado.' }
  $rinoJournal=Get-Content -LiteralPath (Join-Path $rinoBackup 'journal.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if (Test-Path -LiteralPath $rinoPending) {
    $rinoLive=Get-Content -LiteralPath $rinoPending -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($rinoLive.path -eq $rinoJournal.path) { $rinoJournal.status=$rinoLive.status }
  }
  if ((Get-RinoHash (Join-Path $rinoBackup 'backup-index.json')) -ne $rinoJournal.backupIndexSha256) { throw 'Indice de respaldo alterado.' }
  $rinoIndex=Get-Content -LiteralPath (Join-Path $rinoBackup 'backup-index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $rinoRestore=@()
  foreach ($rinoEntry in $rinoIndex) {
    $rinoSource=Get-RinoPath $rinoBackup ('backup/'+$rinoEntry.path)
    if ((Get-RinoHash $rinoSource) -ne $rinoEntry.sha256) { throw "Respaldo alterado: $($rinoEntry.path)" }
    if ($RestoreSettings -or @($rinoJournal.entries | Where-Object path -eq $rinoEntry.path).Count -gt 0) { $rinoRestore+=$rinoEntry }
  }
  foreach ($rinoEntry in $rinoJournal.entries) {
    if (-not (Test-RinoCode $rinoEntry.path)) { throw 'Registro de recuperacion inseguro.' }
    $rinoTarget=Get-RinoPath $rinoRoot $rinoEntry.path
    $rinoHash=Get-RinoHash $rinoTarget
    if ($rinoJournal.status -ne 'applying' -and $rinoHash -ne $rinoEntry.before -and $rinoHash -ne $rinoEntry.after -and $rinoHash -ne $rinoJournal.barrierSha256) { throw "Cambio posterior que requiere revision: $($rinoEntry.path)" }
  }
  if (-not $PSCmdlet.ShouldProcess($rinoRoot,"Restaurar codigo; configuraciones antiguas: $RestoreSettings")) { return }
  $rinoRescue=Get-RinoPath $rinoRoot ('_updates/rescue-'+[guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($rinoRescue) | Out-Null
  Save-RinoSnapshot $rinoRescue | Out-Null
  foreach ($rinoEntry in ($rinoRestore | Sort-Object { $_.path -eq '_Loader.lua' })) {
    Write-RinoBytes (Get-RinoPath $rinoRoot $rinoEntry.path) ([IO.File]::ReadAllBytes((Get-RinoPath $rinoBackup ('backup/'+$rinoEntry.path))))
  }
  $rinoMetadata=@()
  $rinoStorage=Join-Path $rinoRoot 'storage'
  if (Test-Path -LiteralPath $rinoStorage) { $rinoMetadata+=@(Get-ChildItem -LiteralPath $rinoStorage -File | Where-Object Name -match '^profile_\d+\.json$') }
  $rinoShared=Join-Path $rinoRoot '_helper_profiles/shared.json'
  if (Test-Path -LiteralPath $rinoShared) { $rinoMetadata+=Get-Item -LiteralPath $rinoShared }
  foreach ($rinoFile in $rinoMetadata) {
    $rinoData=Read-RinoSettings $rinoFile.FullName
    if ($rinoData.sabuezoUpdater) {
      $rinoData.sabuezoUpdater['version']=$rinoJournal.previousVersion
      $rinoData.sabuezoUpdater['autoInstall']=$false
      $rinoData.sabuezoUpdater['fileHashes']=@{}
      Write-RinoJson $rinoFile.FullName $rinoData
    }
  }
  foreach ($rinoEntry in $rinoJournal.entries) {
    if ($rinoEntry.before -eq $false) {
      $rinoTarget=Get-RinoPath $rinoRoot $rinoEntry.path
      if (Test-Path -LiteralPath $rinoTarget -PathType Leaf) { Remove-Item -LiteralPath $rinoTarget }
    }
  }
  $rinoJournal.status='rolledBack';Write-RinoJson $rinoPending $rinoJournal
  Write-Output "Codigo restaurado. Respaldo del estado reciente: $rinoRescue"
  return
}
$rinoRelease=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ReleaseDirectory).Path).TrimEnd('\')
$rinoManifest=Get-Content -LiteralPath (Join-Path $rinoRelease 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($rinoManifest.installProtocol -ne 1 -or $rinoManifest.version -ne '3.1.0') { throw 'Paquete de RinoBot incompatible.' }
if (Test-Path -LiteralPath (Join-Path $rinoRoot '_helper_dev/development.lock')) { throw 'Esta instalacion tiene un bloqueo de desarrollo. Usa una copia para probar.' }
if (Test-Path -LiteralPath $rinoPending) {
  $rinoPrevious=Get-Content -LiteralPath $rinoPending -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($rinoPrevious.status -notin @('complete','rolledBack','aborted')) { throw 'Recupera primero la instalacion pendiente con -Mode Restore.' }
}
$rinoEntries=@();$rinoSeen=@{}
foreach ($rinoEntry in $rinoManifest.files) {
  if (-not (Test-RinoCode $rinoEntry.path) -or $rinoSeen.ContainsKey($rinoEntry.path.ToLowerInvariant())) { throw 'El paquete contiene una ruta no permitida o duplicada.' }
  $rinoSeen[$rinoEntry.path.ToLowerInvariant()]=$true
  $rinoSource=Get-RinoPath $rinoRelease ('files/'+$rinoEntry.path)
  if ((Get-RinoHash $rinoSource) -ne $rinoEntry.sha256 -or (Get-Item -LiteralPath $rinoSource).Length -ne $rinoEntry.size) { throw "Paquete incompleto: $($rinoEntry.path)" }
  $rinoTarget=Get-RinoPath $rinoRoot $rinoEntry.path
  $rinoOld=Get-RinoHash $rinoTarget
  if ($rinoOld -eq $rinoEntry.sha256) { continue }
  if ($rinoOld -and $rinoOld -notin @($rinoEntry.acceptedSha256)) { throw "Archivo personalizado: $($rinoEntry.path). Se conserva; necesita revision." }
  $rinoEntries+=@{path=$rinoEntry.path;before=$rinoOld;after=$rinoEntry.sha256}
}
if ($rinoEntries.Count -eq 0) { Write-Output 'Todos los archivos de RinoBot ya coinciden.';return }
if (-not $PSCmdlet.ShouldProcess($rinoRoot,"Respaldar todos los datos e instalar RinoBot $($rinoManifest.version) ($($rinoEntries.Count) archivos)")) { return }
$rinoTransactionRoot=Get-RinoPath $rinoRoot '_updates/transactions'
$rinoNumber=1
while (Test-Path -LiteralPath (Join-Path $rinoTransactionRoot "t$rinoNumber")) { $rinoNumber++ }
$rinoTransaction=Get-RinoPath $rinoRoot "_updates/transactions/t$rinoNumber"
[IO.Directory]::CreateDirectory($rinoTransaction) | Out-Null
Save-RinoSnapshot $rinoTransaction | Out-Null
$rinoOldLoader=[IO.File]::ReadAllBytes((Join-Path $rinoRoot '_Loader.lua'))
$rinoPrefix=[IO.File]::ReadAllBytes((Join-Path $rinoScriptDirectory 'recovery-prefix.lua'))
$rinoBarrier=[byte[]]($rinoPrefix+$rinoOldLoader)
$rinoStageLoader=@($rinoEntries | Where-Object path -eq '_Loader.lua').Count -gt 0
if (-not $rinoStageLoader) {
  $rinoLoaderHash=Get-RinoHash (Join-Path $rinoRoot '_Loader.lua')
  $rinoEntries+=@{path='_Loader.lua';before=$rinoLoaderHash;after=$rinoLoaderHash}
}
$rinoHashEngine=[Security.Cryptography.SHA256]::Create()
try { $rinoBarrierHash=[BitConverter]::ToString($rinoHashEngine.ComputeHash($rinoBarrier)).Replace('-','').ToLowerInvariant() } finally { $rinoHashEngine.Dispose() }
$rinoFolder=Split-Path -Leaf $rinoRoot
$rinoPriorVersion='3.0.28'
$rinoVersions=@()
$rinoStorage=Join-Path $rinoRoot 'storage'
if (Test-Path -LiteralPath $rinoStorage) {
  foreach ($rinoFile in (Get-ChildItem -LiteralPath $rinoStorage -File | Where-Object Name -match '^profile_\d+\.json$')) {
    $rinoData=Read-RinoSettings $rinoFile.FullName
    if ($rinoData.sabuezoUpdater.version -match '^\d+\.\d+\.\d+$') { $rinoVersions+= $rinoData.sabuezoUpdater.version }
  }
}
if ($rinoVersions.Count -gt 0) { $rinoPriorVersion=($rinoVersions | Sort-Object {[version]$_} -Descending | Select-Object -First 1) }
$rinoJournal=@{protocol=1;path="/bot/$rinoFolder/_updates/transactions/t$rinoNumber";status='applying';version=$rinoManifest.version;previousVersion=$rinoPriorVersion;entries=@($rinoEntries);awaitBoot=$true;barrierSha256=$rinoBarrierHash;backupIndexSha256=(Get-RinoHash (Join-Path $rinoTransaction 'backup-index.json'))}
Write-RinoJson (Join-Path $rinoTransaction 'journal.json') $rinoJournal
Write-RinoJson ($rinoPending+'.previous') $rinoJournal
Write-RinoJson $rinoPending $rinoJournal
try {
  Write-RinoBytes (Join-Path $rinoRoot '_Loader.lua') $rinoBarrier
  foreach ($rinoEntry in $rinoEntries) {
    if ($rinoEntry.path -ne '_Loader.lua') {
      Write-RinoBytes (Get-RinoPath $rinoRoot $rinoEntry.path) ([IO.File]::ReadAllBytes((Get-RinoPath $rinoRelease ('files/'+$rinoEntry.path))))
    }
  }
  $rinoFinalLoader=if ($rinoStageLoader) { [IO.File]::ReadAllBytes((Get-RinoPath $rinoRelease 'files/_Loader.lua')) } else { $rinoOldLoader }
  Write-RinoBytes (Join-Path $rinoRoot '_Loader.lua') $rinoFinalLoader
  $rinoJournal.status='pendingBoot';Write-RinoJson $rinoPending $rinoJournal
} catch {
  Write-Output "Instalacion interrumpida. Recuperacion disponible en $rinoTransaction"
  & $rinoScriptPath -BotDirectory $rinoRoot -Mode Restore -BackupDirectory $rinoTransaction -Confirm:$false
  throw
}
Write-Output "RinoBot instalado. Abre el cliente para verificar y migrar perfiles. Respaldo: $rinoTransaction"
