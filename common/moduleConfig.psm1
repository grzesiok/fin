$pwdPath=$PWD.Path
$scriptFiles = Get-ChildItem "$pwdPath\config\*.ps1" -Recurse

foreach ($script in $scriptFiles) {
  try {
    . $script.FullName
  } catch [System.Exception] {
    throw
  }
}