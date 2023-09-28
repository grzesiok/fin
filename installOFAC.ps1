$pwdPath=$PWD.Path
Import-Module $pwdPath\common\psqlFunctions.psm1 -Force -Verbose

# Import process
psqlExecute "DROP TABLE if exists dbo.ofac_data;

CREATE TABLE dbo.ofac_data(import_date DATE NOT NULL,
                           xmldata XML,
                           jsondata JSON);

DROP TABLE if exists dbo.ofac_entry;

CREATE TABLE dbo.ofac_entry(uid INTEGER NOT NULL,
                           first_name VARCHAR(200),
                           last_name VARCHAR(200),
                           sdn_type VARCHAR(20) NOT NULL,
                           active_flag VARCHAR(1) NOT NULL,
                           version_from DATE NOT NULL,
                           version_to DATE NOT NULL);

create or replace procedure dbo.pr_ofac_refresh() 
language plpgsql
as $$
declare
  l_begindate DATE;
  l_enddate DATE := to_date('2999-12-31','YYYY-MM-DD');
  ofacdata_row record;
  l_rows_inserted INTEGER;
  l_rows_updated_n INTEGER;
  l_rows_updated_y INTEGER;
  l_rows_deleted INTEGER;
  l_hash_short_left TEXT;
  l_hash_short_right TEXT;
begin
  DELETE FROM dbo.ofac_entry;
  FOR ofacdata_row IN (SELECT t.import_date, t.xmldata, t.hashsum
                       FROM (SELECT t2.import_date, t2.xmldata, t2.hashsum
                             FROM (SELECT od.import_date,
                                          od.xmldata,
                                          sha512(row(od.xmldata)::text::bytea) as hashsum,
                                          first_value(od.import_date) over (partition by sha512(row(od.xmldata)::text::bytea) order by od.import_date asc) as first_import_date
                                   FROM dbo.ofac_data od) t2
                             WHERE t2.import_date = t2.first_import_date) t
                       ORDER BY t.import_date ASC)
  LOOP
    l_hash_short_left := LEFT(encode(ofacdata_row.hashsum, 'hex'), 8);
    l_hash_short_right := RIGHT(encode(ofacdata_row.hashsum, 'hex'), 8);
    RAISE NOTICE 'Processing OFAC date %...', ofacdata_row.import_date;
    l_begindate := to_date(xpath('/mydefns:sdnList/mydefns:publshInformation/mydefns:Publish_Date/text()',
                           ofacdata_row.xmldata,
                           ARRAY[ARRAY['mydefns', 'http://tempuri.org/sdnList.xsd']])::text, '\{MM/DD/YYYY\}');
    /* Delete records which are not in NEW set */
    UPDATE dbo.ofac_entry oe
      SET active_flag = 'N',
          version_to = l_begindate
    WHERE oe.active_flag = 'Y'
      AND NOT EXISTS(SELECT 1
                     FROM xmltable(XMLNAMESPACES('http://tempuri.org/sdnList.xsd' AS mydefns),
                                   '/mydefns:sdnList/mydefns:sdnEntry'
                                   PASSING ofacdata_row.xmldata
                                   COLUMNS uid int PATH 'mydefns:uid') xt
                     WHERE oe.uid = xt.uid);
    GET DIAGNOSTICS l_rows_deleted = ROW_COUNT;
    /* Insert only new records which appear in NEW set but was not visible before */
    INSERT INTO dbo.ofac_entry(uid, first_name, last_name, sdn_type, active_flag, version_from, version_to)
      select xt.uid, xt.first_name, xt.last_name, xt.sdn_type, 'Y', l_begindate, l_enddate
      from xmltable(XMLNAMESPACES('http://tempuri.org/sdnList.xsd' AS mydefns),
                    '/mydefns:sdnList/mydefns:sdnEntry'
                    PASSING ofacdata_row.xmldata
                    COLUMNS uid int PATH 'mydefns:uid',
                            first_name text PATH 'mydefns:firstName',
                            last_name text PATH 'mydefns:lastName',
                            sdn_type text PATH 'mydefns:sdnType') xt
      WHERE NOT EXISTS(SELECT 1
                       FROM dbo.ofac_entry oe
                       WHERE oe.uid = xt.uid);
    GET DIAGNOSTICS l_rows_inserted = ROW_COUNT;
    /* Disable updated only records (old versions) */
    UPDATE dbo.ofac_entry oe
      SET active_flag = 'N',
          version_to = l_begindate
    WHERE oe.active_flag = 'Y'
      AND NOT EXISTS(SELECT 1
                     FROM xmltable(XMLNAMESPACES('http://tempuri.org/sdnList.xsd' AS mydefns),
                                   '/mydefns:sdnList/mydefns:sdnEntry'
                                   PASSING ofacdata_row.xmldata
                                   COLUMNS uid int PATH 'mydefns:uid',
                                           first_name text PATH 'mydefns:firstName',
                                           last_name text PATH 'mydefns:lastName',
                                           sdn_type text PATH 'mydefns:sdnType') xt
                     WHERE oe.uid = xt.uid
                       AND coalesce(oe.first_name, '') = coalesce(xt.first_name, '')
                       AND coalesce(oe.last_name, '') = coalesce(xt.last_name, '')
                       AND coalesce(oe.sdn_type, '') = coalesce(xt.sdn_type, ''));
    GET DIAGNOSTICS l_rows_updated_n = ROW_COUNT;
    /* Insert new versions */
    INSERT INTO dbo.ofac_entry(uid, first_name, last_name, sdn_type, active_flag, version_from, version_to)
      select xt.uid, xt.first_name, xt.last_name, xt.sdn_type, 'Y', l_begindate, l_enddate
      from xmltable(XMLNAMESPACES('http://tempuri.org/sdnList.xsd' AS mydefns),
                    '/mydefns:sdnList/mydefns:sdnEntry'
                    PASSING ofacdata_row.xmldata
                    COLUMNS uid int PATH 'mydefns:uid',
                            first_name text PATH 'mydefns:firstName',
                            last_name text PATH 'mydefns:lastName',
                            sdn_type text PATH 'mydefns:sdnType') xt,
           dbo.ofac_entry oe
      WHERE oe.uid = xt.uid
        AND (coalesce(oe.first_name, '') != coalesce(xt.first_name, '')
          OR coalesce(oe.last_name, '') != coalesce(xt.last_name, '')
          OR coalesce(oe.sdn_type, '') != coalesce(xt.sdn_type, ''));
    GET DIAGNOSTICS l_rows_updated_y = ROW_COUNT;
    RAISE NOTICE 'Processing OFAC date %(%...%) -> INS=% UPDN=% UPDY=% DEL=%', ofacdata_row.import_date, l_hash_short_left, l_hash_short_right, l_rows_inserted, l_rows_updated_n, l_rows_updated_y, l_rows_deleted;
  END LOOP;
end; $$"

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