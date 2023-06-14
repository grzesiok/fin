$pwdPath=$PWD.Path
Import-Module $pwdPath\common\psqlFunctions.psm1 -Force -Verbose

$ofacLoadDateText = (psqlExecute "select max(import_date)+1 from dbo.ofac_data;" "-t").Trim()
if([string]::IsNullOrEmpty($ofacLoadDateText)) {
  # If there is no data in DB load from beginning
  $ofacLoadDateText = (Get-Date).ToString('yyyy-MM-dd')
}
$ofacLoadDate = [Datetime]::ParseExact($ofacLoadDateText, 'yyyy-MM-dd', $null)
if($ofacLoadDate -gt (Get-Date))
{
  Exit 0
}

Write-Output "Loading OFAC data for ($ofacLoadDateText)..."
# Pull data from Endpoint
$WebResponse = Invoke-WebRequest -Uri "http://www.treasury.gov/ofac/downloads/consolidated/consolidated.xml" -Method GET
# If there is no data then skip processing
if ($WebResponse.StatusCode -eq "200") {
  $ofacContent = $WebResponse.Content.replace("'", "''")
  psqlExecute "\echo Loading Stage (dbo.ofac_data) ...
INSERT INTO dbo.ofac_data(import_date, xmldata)
  VALUES(to_date('$ofacLoadDateText','YYYY-MM-DD'), '$ofacContent');"
}

Exit 0