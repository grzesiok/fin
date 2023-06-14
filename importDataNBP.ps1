$pwdPath=$PWD.Path
Import-Module $pwdPath\common\psqlFunctions.psm1 -Force

# If date in parameters is empty then use last date + 1 from DB up to current date
if([string]::IsNullOrEmpty($args[0])) {
  $paramLoadDateText = (psqlExecute "select max(effective_date)+1 from dbo.f_currency_rate;" "-t").Trim()
  if([string]::IsNullOrEmpty($paramLoadDateText)) {
    # If there is no data in DB load from beginning
    $paramLoadDateText = '2002-01-02'
  }
  # Convert date Text to DateTime object
  $currentDate = [Datetime]::ParseExact($paramLoadDateText, 'yyyy-MM-dd', $null)
  $endDate = (Get-Date)
} else {
  $paramLoadDateText = $args[0]
  # Convert date Text to DateTime object
  $currentDate = [Datetime]::ParseExact($paramLoadDateText, 'yyyy-MM-dd', $null)
  $endDate = $startDate
}

if($currentDate -le $endDate) {
  Write-Output "Loading NBP data for ($currentDate, $endDate)..."
  while ($currentDate -le $endDate) {
    $currentDateText = $currentDate.ToString('yyyy-MM-dd')
    # Skip Saturday and Sunday
    if ($currentDate.DayOfWeek.value__ -eq 0 -Or $currentDate.DayOfWeek.value__ -eq 6) {
      $currentDate = $currentDate.AddDays(1)
      Continue
    }
    Write-Output "http://api.nbp.pl/api/exchangerates/tables/C/$currentDateText"
    # Pull data from Endpoint
    $WebResponse = Invoke-WebRequest -Uri "http://api.nbp.pl/api/exchangerates/tables/C/$currentDateText" -Method GET
    # If there is no data then skip processing
    if ($WebResponse.StatusCode -ne "200") {
      $currentDate = $currentDate.AddDays(1)
      Continue
    }
    # Parse parameters and import to DB
    $NbpCurrencyRates = (($WebResponse.Content | ConvertFrom-Json).rates | ConvertTo-Json  -Compress)
    $NbpEffectiveDate = ($WebResponse.Content | ConvertFrom-Json).effectiveDate
    $NbpTradingDate = ($WebResponse.Content | ConvertFrom-Json).tradingDate
    psqlExecute "SET client_encoding = 'UTF8';
\echo Loading Dimesinsion (dbo.d_currency) ...
UPDATE dbo.d_currency
  SET version_is_active = 'N',
      version_valid_to = to_date('$NbpEffectiveDate','YYYY-MM-DD')
WHERE version_is_active = 'Y'
  AND EXISTS(SELECT 1
             FROM json_array_elements_text('$NbpCurrencyRates')
             WHERE currency_code = replace(json_extract_path(value::json, 'code')::text, '""', '')
               AND (coalesce(currency_name, '~') != coalesce(replace(json_extract_path(value::json, 'currency')::text, '""', ''), '~')
                 OR coalesce(country, '~') != coalesce(replace(json_extract_path(value::json, 'country')::text, '""', ''), '~')
                 OR coalesce(symbol, '~') != coalesce(replace(json_extract_path(value::json, 'symbol')::text, '""', ''), '~')));
INSERT INTO dbo.d_currency(currency_code,
                           currency_name,
                           country,
                           symbol,
                           version_valid_from,
                           version_valid_to,
                           version_is_active)
  SELECT replace(json_extract_path(value::json, 'code')::text, '""', ''),
         replace(json_extract_path(value::json, 'currency')::text, '""', ''),
         replace(json_extract_path(value::json, 'country')::text, '""', ''),
         replace(json_extract_path(value::json, 'symbol')::text, '""', ''),
         to_date('$NbpEffectiveDate','YYYY-MM-DD'),
         TO_DATE('29991231','YYYYMMDD'),
         'Y'
  FROM json_array_elements_text('$NbpCurrencyRates')
  WHERE NOT EXISTS(SELECT 1
                   FROM dbo.d_currency
                   WHERE EXISTS (SELECT 1
                                 FROM json_array_elements_text('$NbpCurrencyRates')
                                 WHERE currency_code = replace(json_extract_path(value::json, 'code')::text, '""', ''))
                                   AND version_is_active = 'Y');
\echo Loading Fact (dbo.f_currency_rate) ...
INSERT INTO dbo.f_currency_rate(currency_id,
                                trading_date,
                                effective_date,
                                bid,
                                ask)
  SELECT dcur.currency_id,
         to_date('$NbpEffectiveDate','YYYY-MM-DD'),
         to_date('$NbpEffectiveDate','YYYY-MM-DD'),
         json_extract_path(value::json, 'bid')::text::DECIMAL,
         json_extract_path(value::json, 'ask')::text::DECIMAL
  FROM json_array_elements_text('$NbpCurrencyRates') base,
       dbo.d_currency dcur
  WHERE dcur.currency_code = replace(json_extract_path(base.value::json, 'code')::text, '""', '')
    AND dcur.version_is_active = 'Y'"
    $currentDate = $currentDate.AddDays(1)
  }
}

Exit 0