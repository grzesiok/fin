$pwdPath=$PWD.Path
$scriptFiles = Get-ChildItem "$pwdPath\config\*.ps1" -Recurse

foreach ($script in $scriptFiles) {
  try {
    $scriptFullName = $script.FullName
    Write-Output "Applying confing from $scriptFullName ..."
    . $scriptFullName
  } catch [System.Exception] {
    throw
  }
}