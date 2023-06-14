$pwdPath=$PWD.Path
Import-Module $pwdPath\common\psqlFunctions.psm1 -Force -Verbose

# Import process
psqlExecute "DROP TABLE if exists dbo.d_date;

CREATE TABLE dbo.d_date
(
  date_id              smallint NOT NULL,
  date_actual              DATE NOT NULL,
  epoch                    BIGINT NOT NULL,
  day_suffix               VARCHAR(4) NOT NULL,
  day_name                 VARCHAR(9) NOT NULL,
  day_of_week              INT NOT NULL,
  day_of_month             INT NOT NULL,
  day_of_quarter           INT NOT NULL,
  day_of_year              INT NOT NULL,
  week_of_month            INT NOT NULL,
  week_of_year             INT NOT NULL,
  week_of_year_iso         CHAR(10) NOT NULL,
  month_actual             INT NOT NULL,
  month_name               VARCHAR(9) NOT NULL,
  month_name_abbreviated   CHAR(3) NOT NULL,
  quarter_actual           INT NOT NULL,
  quarter_name             VARCHAR(9) NOT NULL,
  year_actual              INT NOT NULL,
  first_day_of_week        DATE NOT NULL,
  last_day_of_week         DATE NOT NULL,
  first_day_of_month       DATE NOT NULL,
  last_day_of_month        DATE NOT NULL,
  first_day_of_quarter     DATE NOT NULL,
  last_day_of_quarter      DATE NOT NULL,
  first_day_of_year        DATE NOT NULL,
  last_day_of_year         DATE NOT NULL,
  mmyyyy                   CHAR(6) NOT NULL,
  mmddyyyy                 CHAR(10) NOT NULL,
  weekend_indr             BOOLEAN NOT NULL
);

ALTER TABLE dbo.d_date ADD CONSTRAINT d_date_pk PRIMARY KEY (date_id);

CREATE INDEX d_date_01_ix
  ON dbo.d_date(date_actual);

COMMIT;

INSERT INTO dbo.d_date
SELECT datum_id::smallint AS date_id,
       datum AS date_actual,
       EXTRACT(EPOCH FROM datum) AS epoch,
       TO_CHAR(datum, 'fmDDth') AS day_suffix,
       TO_CHAR(datum, 'TMDay') AS day_name,
       EXTRACT(ISODOW FROM datum) AS day_of_week,
       EXTRACT(DAY FROM datum) AS day_of_month,
       datum - DATE_TRUNC('quarter', datum)::DATE + 1 AS day_of_quarter,
       EXTRACT(DOY FROM datum) AS day_of_year,
       TO_CHAR(datum, 'W')::INT AS week_of_month,
       EXTRACT(WEEK FROM datum) AS week_of_year,
       EXTRACT(ISOYEAR FROM datum) || TO_CHAR(datum, '""-W""IW-') || EXTRACT(ISODOW FROM datum) AS week_of_year_iso,
       EXTRACT(MONTH FROM datum) AS month_actual,
       TO_CHAR(datum, 'TMMonth') AS month_name,
       TO_CHAR(datum, 'Mon') AS month_name_abbreviated,
       EXTRACT(QUARTER FROM datum) AS quarter_actual,
       CASE
           WHEN EXTRACT(QUARTER FROM datum) = 1 THEN 'First'
           WHEN EXTRACT(QUARTER FROM datum) = 2 THEN 'Second'
           WHEN EXTRACT(QUARTER FROM datum) = 3 THEN 'Third'
           WHEN EXTRACT(QUARTER FROM datum) = 4 THEN 'Fourth'
           END AS quarter_name,
       EXTRACT(YEAR FROM datum) AS year_actual,
       datum + (1 - EXTRACT(ISODOW FROM datum))::INT AS first_day_of_week,
       datum + (7 - EXTRACT(ISODOW FROM datum))::INT AS last_day_of_week,
       datum + (1 - EXTRACT(DAY FROM datum))::INT AS first_day_of_month,
       (DATE_TRUNC('MONTH', datum) + INTERVAL '1 MONTH - 1 day')::DATE AS last_day_of_month,
       DATE_TRUNC('quarter', datum)::DATE AS first_day_of_quarter,
       (DATE_TRUNC('quarter', datum) + INTERVAL '3 MONTH - 1 day')::DATE AS last_day_of_quarter,
       TO_DATE(EXTRACT(YEAR FROM datum) || '-01-01', 'YYYY-MM-DD') AS first_day_of_year,
       TO_DATE(EXTRACT(YEAR FROM datum) || '-12-31', 'YYYY-MM-DD') AS last_day_of_year,
       TO_CHAR(datum, 'mmyyyy') AS mmyyyy,
       TO_CHAR(datum, 'mmddyyyy') AS mmddyyyy,
       CASE
           WHEN EXTRACT(ISODOW FROM datum) IN (6, 7) THEN TRUE
           ELSE FALSE
           END AS weekend_indr
FROM (SELECT '1980-01-01'::DATE + SEQUENCE.DAY AS datum, SEQUENCE.DAY AS datum_id
      FROM GENERATE_SERIES(0, 30000) AS SEQUENCE (DAY)
      GROUP BY SEQUENCE.DAY) DQ
ORDER BY 1;

COMMIT;"

psqlExecute "DROP TABLE if exists dbo.d_time;

CREATE TABLE dbo.d_time
(
  time_id              int NOT NULL,
  time_of_day              time without time zone NOT NULL,
  hour                    smallint NOT NULL,
  minute               smallint NOT NULL,
  minute_of_day              smallint NOT NULL,
  second_of_day              INT NOT NULL,
  day_time_name             text NOT NULL,
  day_night             text NOT NULL
);

ALTER TABLE dbo.d_time ADD CONSTRAINT d_time_pk PRIMARY KEY (time_id);

CREATE INDEX d_time_01_ix
  ON dbo.d_time(time_of_day);

COMMIT;

insert into dbo.d_time(time_id,time_of_day,hour ,minute,minute_of_day,second_of_day,day_time_name,day_night)
select time_val_secs as time_id,
       time_val::time AS TimeOfDay,
	extract(hour from time_val) as Hour, 
	extract(minute from time_val) as minute, 
	extract(hour from time_val)*60 + extract(minute from time_val) as minute_of_day,
	time_val_secs as second_of_day,
	case when to_char(time_val, 'hh24:mi:ss') between '06:00:00' and '08:29:59'
		then 'Morning'
	     when to_char(time_val, 'hh24:mi:ss') between '08:30:00' and '11:59:59'
		then 'AM'
	     when to_char(time_val, 'hh24:mi:ss') between '12:00:00' and '17:59:59'
		then 'PM'
	     when to_char(time_val, 'hh24:mi:ss') between '18:00:00' and '22:29:59'
		then 'Evening'
	     else 'Night'
	end as DaytimeName,
	case when to_char(time_val, 'hh24:mi') between '07:00' and '19:59' then 'Day'
	     else 'Night'
	end AS DayNight
from (SELECT '0:00:00'::time + (sequence.time_val_secs || ' seconds')::interval AS time_val, time_val_secs
	FROM generate_series(0,86399) AS sequence(time_val_secs)
     ) DQ
order by 1"

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


psqlExecute "DROP TABLE if exists dbo.ofac_data;

CREATE TABLE dbo.ofac_data(import_date DATE NOT NULL,
                           xmldata XML);"

## Import Schedule
# Cleaning up schedules
Unregister-ScheduledTask -TaskName ‘ImportDataNBP’ -Confirm:$false
Unregister-ScheduledTask -TaskName ‘ImportDataOFAC’ -Confirm:$false
# Setup new ones
$scheduledTime = New-ScheduledTaskTrigger -At 4PM -Daily
$scheduledTaskSettingsSet = New-ScheduledTaskSettingsSet -Hidden
# NBP
$scheduledActionNBP = New-ScheduledTaskAction -Execute “PowerShell.exe ./importDataNBP.ps1” -WorkingDirectory D:\Data\financial
Register-ScheduledTask -TaskName “ImportDataNBP” -Trigger $scheduledTime -Action $scheduledActionNBP -Settings $scheduledTaskSettingsSet
# OFAC
$scheduledActionOFAC = New-ScheduledTaskAction -Execute “PowerShell.exe ./importDataOFAC.ps1” -WorkingDirectory D:\Data\financial
Register-ScheduledTask -TaskName “ImportDataOFAC” -Trigger $scheduledTime -Action $scheduledActionOFAC -Settings $scheduledTaskSettingsSet

Exit 0