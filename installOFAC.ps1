$pwdPath=$PWD.Path
Import-Module $pwdPath\common\psqlFunctions.psm1 -Force -Verbose

# Import process
psqlExecute "DROP TABLE if exists dbo.ofac_data;

CREATE TABLE dbo.ofac_data(import_date DATE NOT NULL,
                           jsondata JSON);"

## Import Schedule
# Cleaning up schedules
Unregister-ScheduledTask -TaskName ‘ImportDataOFAC’ -Confirm:$false
# Setup new ones
$scheduledTime = New-ScheduledTaskTrigger -At 4PM -Daily
$scheduledTaskSettingsSet = New-ScheduledTaskSettingsSet -Hidden
# OFAC
$scheduledActionOFAC = New-ScheduledTaskAction -Execute “PowerShell.exe ./importDataOFAC.ps1” -WorkingDirectory D:\Data\financial
Register-ScheduledTask -TaskName “ImportDataOFAC” -Trigger $scheduledTime -Action $scheduledActionOFAC -Settings $scheduledTaskSettingsSet

Exit 0