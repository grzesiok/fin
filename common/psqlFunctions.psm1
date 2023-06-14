$pwdPath=$PWD.Path
Import-Module $pwdPath\common\moduleConfig.psm1 -Force -Verbose

function psqlExecute([string]$command, [string]$optionalParam)
{
  $Env:PGPASSWORD = $global:config.psqlConfig.psqlPassword
  # -b -> print all messages + queries to screen
  # -X -> stop read .psqlrc file
  # ON_ERROR_STOP=1 -> stop when first fail occur
  $tmpFilePath = $global:config.dataDir+"/tmp_script.sql"
  $command | Out-File -FilePath $tmpFilePath
  $pinfo = New-Object System.Diagnostics.ProcessStartInfo
  $pinfo.FileName = $global:config.psqlConfig.psqlPath
  $pinfo.RedirectStandardError = $true
  $pinfo.RedirectStandardOutput = $true
  $pinfo.UseShellExecute = $false
  $jdbcPath = $global:config.psqlConfig.psqlJDBC
  $pinfo.Arguments = "--file=`"$tmpFilePath`" $optionalParam -b -X --variable=ON_ERROR_STOP=1 $jdbcPath"
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $pinfo
  $p.Start() | Out-Null
  $p.WaitForExit()
  $stdout = $p.StandardOutput.ReadToEnd()
  Remove-Item -Path $tmpFilePath
  return $stdout
}