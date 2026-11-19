-- Built-in adapters. Order matters: first match wins.
-- Additional local rules live in _helper_client/clients.json
HelperClientRegistry={
  -- Detected by path (most reliable when folder exists)
  {id='valkaris', name='Valkaris', path='/valkaris/', adapter='vBot/valkaris_compat.lua',
   caps={hasRawIO=true, hasStyleFromString=true, hasEquipItemId=true}},
  -- Valkaris Next Gen (client 3.1). Its data folder is "Valkaris Client", so the path above never
  -- matches it and it used to fall back to "Cliente generico". It reads and writes files natively,
  -- so it needs no adapter.
  {id='valkaris-ng', name='Valkaris Next Gen', path='/valkaris client/',
   caps={hasRawIO=true, hasStyleFromString=true, hasEquipItemId=true}},
  {id='aurera', name='Aurera', path='/otclientv8/aurera/',
   caps={hasNativeSpellAim=false}},
  -- Thornia (OTClientV8 "thorniav8-1.0", protocol 1100). Reads and writes files
  -- natively and imports styles from strings: no adapter.
  {id='thornia', name='Thornia', path='/thornia',
   caps={hasRawIO=true, hasStyleFromString=true, hasEquipItemId=true, hasNativeSpellAim=false}},
  -- Generic fallback
  {id='generic', name='Cliente generico'},
}
