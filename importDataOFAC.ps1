$pwdPath=$PWD.Path
Import-Module $pwdPath\common\psqlFunctions.psm1 -Force -Verbose
Import-Module $pwdPath\common\commonFunctions.psm1 -Force -Verbose

$ofacLoadDateText = (psqlExecute "select max(import_date)+1 from dbo.ofac_data;" "-t").Trim()
if([string]::IsNullOrEmpty($ofacLoadDateText)) {
  # If there is no data in DB load from beginning
  $ofacLoadDateText = (Get-Date).ToString('yyyy-MM-dd')
}
$ofacLoadDate = [Datetime]::ParseExact($ofacLoadDateText, 'yyyy-MM-dd', $null)
if(($ofacLoadDate -lt (Get-Date)) -or ($ofacLoadDate -eq (Get-Date)))
{
  # For missing entries we should only import todays report
  $ofacLoadDateText = (Get-Date).ToString('yyyy-MM-dd')
  Write-Output "Loading OFAC data for ($ofacLoadDateText)..."
  # Pull data from Endpoint
  $WebResponse = Invoke-WebRequest -Uri "http://www.treasury.gov/ofac/downloads/consolidated/consolidated.xml" -Method GET
  # If there is no data then skip processing
  if ($WebResponse.StatusCode -eq "200") {
    # Get XML from OFAC page
    $ofacContentXML = $WebResponse.Content.replace("'", "''")
    # Print Summary to STDOUT
    [xml]$ofacContentXML.sdnList.publshInformation
    # Translate it to JSON format
    $ofacContentJSON = [xml[]] $ofacContentXML | ConvertFrom-Xml | ConvertTo-Json -Depth 10
    # Save at DB
    psqlExecute "\echo Loading Stage (dbo.ofac_data) ...
INSERT INTO dbo.ofac_data(import_date, xmldata, jsondata)
  VALUES(to_date('$ofacLoadDateText','YYYY-MM-DD'), '$ofacContentXML', '$ofacContentJSON');"
  }
}
psqlExecute "\echo Refreshing OFAC data ...
call dbo.pr_ofac_refresh();"

Exit 0