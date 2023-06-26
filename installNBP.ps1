$pwdPath=$PWD.Path
Import-Module $pwdPath\common\psqlFunctions.psm1 -Force -Verbose

# Import process

psqlExecute "ALTER TABLE IF EXISTS dbo.f_currency_rate DROP CONSTRAINT IF EXISTS f_currency_rate_fk01;

DROP TABLE if exists dbo.d_currency;

DROP SEQUENCE if exists dbo.d_currency_seq;

CREATE SEQUENCE dbo.d_currency_seq;

create table dbo.d_currency
(
  currency_id int NOT NULL DEFAULT nextval('dbo.d_currency_seq'),
  currency_code VARCHAR(20) NOT NULL,
  currency_name VARCHAR(50),
  country VARCHAR(50),
  symbol VARCHAR(50),
  version_valid_from DATE NOT NULL,
  version_valid_to DATE NOT NULL,
  version_is_active VARCHAR(1) NOT NULL
);

ALTER TABLE dbo.d_currency ADD CONSTRAINT d_currency_pk PRIMARY KEY (currency_id);

ALTER SEQUENCE dbo.d_currency_seq OWNED BY dbo.d_currency.currency_id;"

psqlExecute "DROP TABLE if exists dbo.f_currency_rate;

create table dbo.f_currency_rate
(
  currency_id int NOT NULL,
  trading_date DATE NOT NULL,
  effective_date DATE NOT NULL,
  bid NUMERIC NOT NULL,
  ask NUMERIC NOT NULL
);

ALTER TABLE dbo.f_currency_rate ADD CONSTRAINT f_currency_rate_fk01 FOREIGN KEY (currency_id) REFERENCES dbo.d_currency (currency_id);"

## Import Schedule
# Cleaning up schedules
Unregister-ScheduledTask -TaskName ‘ImportDataNBP’ -Confirm:$false
# Setup new ones
$scheduledTime = New-ScheduledTaskTrigger -At 4PM -Daily
$scheduledTaskSettingsSet = New-ScheduledTaskSettingsSet -Hidden
# NBP
$scheduledActionNBP = New-ScheduledTaskAction -Execute “PowerShell.exe ./importDataNBP.ps1” -WorkingDirectory D:\Data\financial
Register-ScheduledTask -TaskName “ImportDataNBP” -Trigger $scheduledTime -Action $scheduledActionNBP -Settings $scheduledTaskSettingsSet

Exit 0