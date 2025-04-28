----------------------------------------------------------------------------------------
--
-- File name:   escp_collect_statspack.sql (2024-11-25)
--
--              Enkitec Sizing and Capacity Planing eSCP
--
-- Purpose:     Collect Resources Metrics for an Oracle Database
--
-- Author:      Carlos Sierra, Abel Macias, Jorge Barba
--
-- Usage:       Extract from Statspack a subset of:
--
--                  view                         resource(s)
--                  ---------------------------- -----------------
--                  STATS$ACTIVE_SESS_HISTORY CPU
--                  STATS$SGA                 MEM
--                  STATS$PGASTAT             MEM
--                  DBA_views (nonAWR)        DISK
--                  STATS$SYSSTAT             IOPS MBPS PHYR PHYW NETW IC
--                  STATS$DLM_MISC            IC
--                  STATS$OSSTAT              OS
--
--              Collections from this script are consumed by the ESCP tool.
--
-- Example:     # cd escp_collect
--              # sqlplus / as sysdba
--              SQL> START sql/escp_master.sql
--
-- Notes:       Developed and tested on 12.2
--
-- Warning:     Requires statspack installation
--
-- Modified on November 2025 to place con_id on END
-- Modified on October 2024 to add CPUINFO and more COLLECT fields
--                          to redefine min_instance_host_id as original
--                          to redefine escp_host_name_short as original
--                          to execute from esp_master.sql
-- Modified on February 2024 to support escp_config.sql
-- Modified on January 2024 to support 1317265.1, redefine escp_host_name_short, id dbrole
-- Modified on Feburary 2023 to redefine min_instance_host_id
---------------------------------------------------------------------------------------

DEFINE ESCP_DATE_FORMAT = 'YYYY-MM-DD"T"HH24:MI:SS';
-- To support Date Range
DEF escp_timestamp_format = 'YYYY-MM-DD"T"HH24:MI:SS.FF';
DEF escp_timestamp_tz_format = 'YYYY-MM-DD"T"HH24:MI:SS.FFTZH:TZM';
-- 

SET TERM OFF ECHO OFF FEED OFF VER OFF HEA OFF PAGES 0 COLSEP ', ' LIN 32767 TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 100 NUM 20 SQLBL ON BLO . RECSEP OFF;

ALTER SESSION SET NLS_NUMERIC_CHARACTERS = ".,";
ALTER SESSION SET NLS_SORT = 'BINARY';
ALTER SESSION SET NLS_COMP = 'BINARY';
ALTER SESSION SET NLS_DATE_FORMAT = '&&ESCP_DATE_FORMAT.';
ALTER SESSION SET NLS_TIMESTAMP_FORMAT = '&&ESCP_DATE_FORMAT.';

-- Get dbid
COL escp_this_dbid NEW_V escp_this_dbid;
SELECT TRIM(TO_CHAR(NVL(TO_NUMBER('&&escp_conf_dbid.'), dbid))) escp_this_dbid FROM v$database
/

-- To support Date Range
-- get collection days escp_collection_days
DEF escp_collection_days = '&&ESCP_MAX_DAYS.';
COL escp_collection_days NEW_V escp_collection_days;
SELECT NVL(TO_CHAR(LEAST(CEIL(sysdate-min(SNAP_TIME)), TO_NUMBER('&&ESCP_MAX_DAYS.'))), '&&ESCP_MAX_DAYS.') escp_collection_days FROM stats$snapshot WHERE dbid = &&escp_this_dbid;

-- To support Date Range
COL escp_history_days NEW_V escp_history_days;
-- range: takes at least 31 days and at most as many as actual history, with a default of 31. parameter restricts within that range. 
SELECT TO_CHAR(LEAST(CEIL(SYSDATE - CAST(MIN(snap_time) AS DATE)), TO_NUMBER('&&escp_collection_days.'))) escp_history_days FROM stats$snapshot WHERE dbid = &&escp_this_dbid.;
SELECT TO_CHAR(TO_DATE('&&escp_conf_date_to.', 'YYYY-MM-DD') - TO_DATE('&&escp_conf_date_from.', 'YYYY-MM-DD') + 1) escp_history_days FROM DUAL WHERE '&&escp_conf_date_from.' != 'YYYY-MM-DD' AND '&&escp_conf_date_to.' != 'YYYY-MM-DD';

select to_number(nvl('&&escp_history_days.','1')) escp_history_days from dual;

COL escp_date_from NEW_V escp_date_from;
COL escp_date_to   NEW_V escp_date_to;
SELECT CASE '&&escp_conf_date_from.' WHEN 'YYYY-MM-DD' THEN TO_CHAR(SYSDATE - &&escp_history_days., '&&escp_date_format.') ELSE '&&escp_conf_date_from.T00:00:00' END escp_date_from FROM DUAL;
SELECT CASE '&&escp_conf_date_to.'   WHEN 'YYYY-MM-DD' THEN TO_CHAR(SYSDATE, '&&escp_date_format.') ELSE '&&escp_conf_date_to.T23:59:59' END escp_date_to FROM DUAL;

-- snapshot ranges
DEF escp_minimum_snap_id=''
DEF escp_maximum_snap_id=''
COL escp_minimum_snap_id NEW_V escp_minimum_snap_id;
SELECT NVL(TO_CHAR(MIN(snap_id)), '0') escp_minimum_snap_id FROM stats$snapshot WHERE dbid = &&escp_this_dbid. AND snap_time > TO_DATE('&&escp_date_from.', '&&escp_date_format.');
SELECT '-1' escp_minimum_snap_id FROM DUAL WHERE TRIM('&&escp_minimum_snap_id.') IS NULL;
COL escp_maximum_snap_id NEW_V escp_maximum_snap_id;
SELECT NVL(TO_CHAR(MAX(snap_id)), '&&escp_minimum_snap_id.') escp_maximum_snap_id FROM stats$snapshot WHERE dbid = &&escp_this_dbid. AND snap_time < TO_DATE('&&escp_date_to.', '&&escp_date_format.');
SELECT '-1' escp_maximum_snap_id FROM DUAL WHERE TRIM('&&escp_maximum_snap_id.') IS NULL;

/* Sentences will change
From: h.snap_id >= &&escp_min_snap_id.
To: h.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
From: h.sample_time >= SYSTIMESTAMP - &&escp_collection_days.
To: h.sample_time BETWEEN TO_TIMESTAMP('&&escp_date_from.','&&escp_timestamp_format.') 
              AND TO_TIMESTAMP('&&escp_date_to.','&&escp_timestamp_format.')
*/
-- all that to support Date Range


-- get host name (up to 30, stop before first '.', no special characters)
-- It is possible to collect from standby and that is a different host than the primary stored in the historic tables
DEF escp_host_name_short = '';
COL escp_host_name_short NEW_V escp_host_name_short FOR A30;
SELECT LOWER(SUBSTR(SYS_CONTEXT('USERENV', 'SERVER_HOST'), 1, 30)) escp_host_name_short FROM DUAL;

SELECT SUBSTR('&&escp_host_name_short.', 1, INSTR('&&escp_host_name_short..', '.') - 1) escp_host_name_short FROM DUAL;
SELECT TRANSLATE('&&escp_host_name_short.',
'abcdefghijklmnopqrstuvwxyz0123456789-_ ''`~!@#$%&*()=+[]{}\|;:",.<>/?'||CHR(0)||CHR(9)||CHR(10)||CHR(13)||CHR(38),
'abcdefghijklmnopqrstuvwxyz0123456789-_') escp_host_name_short FROM DUAL;



-- get database name (up to 10, stop before first '.', no special characters)
COL escp_dbname_short NEW_V escp_dbname_short FOR A10;
SELECT LOWER(SUBSTR(SYS_CONTEXT('USERENV', 'DB_NAME'), 1, 10)) escp_dbname_short FROM DUAL;
SELECT SUBSTR('&&escp_dbname_short.', 1, INSTR('&&escp_dbname_short..', '.') - 1) escp_dbname_short FROM DUAL;
SELECT TRANSLATE('&&escp_dbname_short.',
'abcdefghijklmnopqrstuvwxyz0123456789-_ ''`~!@#$%&*()=+[]{}\|;:",.<>/?'||CHR(0)||CHR(9)||CHR(10)||CHR(13)||CHR(38),
'abcdefghijklmnopqrstuvwxyz0123456789-_') escp_dbname_short FROM DUAL;

-- get collection date
DEF escp_collection_yyyymmdd_hhmi = '';
COL escp_collection_yyyymmdd_hhmi NEW_V escp_collection_yyyymmdd_hhmi FOR A13;
SELECT TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MI') escp_collection_yyyymmdd_hhmi FROM DUAL;

COL escp_this_inst_num NEW_V escp_this_inst_num;
SELECT 'get_instance_number', TO_CHAR(instance_number) escp_this_inst_num FROM v$instance
/

/* The min_snap_id substituted by escp_minimum_snap_id
DEF escp_min_snap_id = '';
COL escp_min_snap_id NEW_V escp_min_snap_id;
SELECT 'get_min_snap_id', TO_CHAR(MIN(snap_id)) escp_min_snap_id FROM dba_hist_snapshot WHERE dbid = &&escp_this_dbid. AND CAST(begin_interval_time AS DATE) > SYSDATE - &&escp_collection_days.
/
SELECT NVL('&&escp_min_snap_id.','0') escp_min_snap_id FROM DUAL
/
*/

-- To support down to 8i 
DEF escp_dbuname ='&&escp_dbname_short.';
COL escp_dbuname NEW_V escp_dbuname
SELECT db_unique_name escp_dbuname FROM v$database;

DEF escp_platform ='Unknown';
COL escp_platform NEW_V escp_platform
SELECT platform_name escp_platform FROM v$database;

-- get primary/standby state
DEF escp_dbrole=''
COL escp_dbrole NEW_V escp_dbrole
SELECT DECODE(DATABASE_ROLE,'PRIMARY','','_s') escp_dbrole from v$database;

-- get container info
DEF env_is_cdb = 'N'
COL env_is_cdb NEW_V env_is_cdb;

DEF env_con_id = '-1';
COL env_con_id NEW_V env_con_id;

DEF env_pdb_name = 'NONE'
COL env_pdb_name NEW_V env_pdb_name;

SELECT /* ignore if it fails to parse */ 
       'Y' env_is_cdb
      ,SYS_CONTEXT('USERENV','CON_ID') env_con_id 
      ,SYS_CONTEXT('USERENV', 'CON_NAME') env_pdb_name 
  FROM v$pdbs 
fetch first row only;

DEF escp_aux_stats='(select null pname, null pval1,null pval2 FROM DUAL WHERE 1=0)'
COL escp_aux_stats NEW_V escp_aux_stats
SELECT 'SYS.AUX_STATS$'  escp_aux_stats
FROM  all_tables 
WHERE table_name='AUX_STATS$';

DEFINE is_cdb = '&&ENV_IS_CDB.'
DEFINE escp_con_id = '&&ENV_CON_ID.'
DEFINE escp_pdb_name = '&&ENV_PDB_NAME.'

@@escp_pre_products.sql
DEF;

---------------------------------------------------------------------------------------
def escp_tail=&&escp_host_name_short._&&escp_dbname_short._&&escp_collection_yyyymmdd_hhmi.&&is_cdb.&&escp_dbrole..csv
SPO escp_&&escp_tail.;

COL escp_metric_group    FOR A8;
COL escp_metric_acronym  FOR A16;
COL escp_instance_number FOR A4;
COL escp_end_date        FOR A20;
COL escp_value           FOR A128;

-- header
SELECT 'METGROUP'       escp_metric_group,
       'METRIC_ACRONYM' escp_metric_acronym,
       'INST'           escp_instance_number,
       'END_DATE'       escp_end_date,
       'VALUE'          escp_value 
  FROM DUAL
/

SELECT 'BEGIN'                    escp_metric_group,
       d.name                     escp_metric_acronym,
       TO_CHAR(i.instance_number) escp_instance_number,
       SYSDATE                    escp_end_date,
       i.host_name                escp_value 
  FROM v$instance i, 
       v$database d
/

-- collection user
SELECT 'COLLECT' escp_metric_group,
       'USER'    escp_metric_acronym,
       NULL      escp_instance_number,
       NULL      escp_end_date,
       USER      escp_value 
  FROM v$instance
/

-- collection days
SELECT 'COLLECT'                                  escp_metric_group,
       'DAYS'                                     escp_metric_acronym,
       NULL                                       escp_instance_number,
       '&&escp_date_to.'                          escp_end_date,
       to_char('&&escp_history_days.')            escp_value 
  FROM DUAL
/

SELECT 'COLLECT'                                  escp_metric_group,
       'DB_ROLE'                                  escp_metric_acronym,
       NULL                                       escp_instance_number,
       NULL                                       escp_end_date,
       DATABASE_ROLE                              escp_value 
  FROM v$database
/

SELECT 'COLLECT'                                  escp_metric_group,
       'DICT'                                     escp_metric_acronym,
       NULL                                       escp_instance_number,
       NULL                                       escp_end_date,
       'STATS$'                                   escp_value 
  FROM DUAL
/

SELECT 'COLLECT'                                  escp_metric_group,
       'PDB'                                      escp_metric_acronym,
       NULL                                       escp_instance_number,
       NULL                                       escp_end_date,
       '&&ESCP_PDB_NAME.'                         escp_value 
  FROM DUAL
/

---------------------------------------------------------------------------------------
-- For a future project, to help estimate RPC from CPUSPEEDNW. 
---------------------------------------------------------------------------------------

SELECT 'COLLECT'        escp_metric_group,
       PNAME            escp_metric_acronym,
       NULL             escp_instance_number,
       NULL             escp_end_date,
       NVL(to_char(PVAL1),PVAL2) escp_value 
  FROM &&escp_aux_stats.
 WHERE PVAL1 is not null or PVAL2 is not null;


---------------------------------------------------------------------------------------

spool off
HOS touch cpuinfo_append.txt
HOS cat cpuinfo_append.txt >> escp_&&escp_tail.
spool escp_&&escp_tail. app;

---------------------------------------------------------------------------------------

-- database dbid
SELECT 'DATABASE'       escp_metric_group,
       'DBID'           escp_metric_acronym,
       NULL             escp_instance_number,
       NULL             escp_end_date,
       TO_CHAR(dbid)    escp_value 
  FROM v$database
/

-- database name
SELECT 'DATABASE'       escp_metric_group,
       'NAME'           escp_metric_acronym,
       NULL             escp_instance_number,
       NULL             escp_end_date,
       name             escp_value 
  FROM v$database
/

-- database created
SELECT 'DATABASE'       escp_metric_group,
       'CREATED'        escp_metric_acronym,
       NULL             escp_instance_number,
       NULL             escp_end_date,
       TO_CHAR(created) escp_value 
  FROM v$database
/

-- database db_unique_name
SELECT 'DATABASE'       escp_metric_group,
       'DB_UNIQUE_NAME' escp_metric_acronym,
       NULL             escp_instance_number,
       NULL             escp_end_date,
       '&&escp_dbuname.'   escp_value 
  FROM DUAL
/

-- database instance_name_min
SELECT 'DATABASE'         escp_metric_group,
       'INST_NAME_MIN'    escp_metric_acronym,
       NULL               escp_instance_number,
       NULL               escp_end_date,
       MIN(instance_name) escp_value 
  FROM STATS$database_instance
 WHERE dbid = &&escp_this_dbid.
/

-- database instance_name_max
SELECT 'DATABASE'         escp_metric_group,
       'INST_NAME_MAX'    escp_metric_acronym,
       NULL               escp_instance_number,
       NULL               escp_end_date,
       MAX(instance_name) escp_value 
  FROM STATS$database_instance
 WHERE dbid = &&escp_this_dbid.
/

-- database host_name_min
SELECT 'DATABASE'      escp_metric_group,
       'HOST_NAME_MIN' escp_metric_acronym,
       NULL            escp_instance_number,
       NULL            escp_end_date,
       MIN(host_name)  escp_value 
  FROM STATS$database_instance
 WHERE dbid = &&escp_this_dbid.
/

-- database host_name_max
SELECT 'DATABASE'      escp_metric_group,
       'HOST_NAME_MAX' escp_metric_acronym,
       NULL            escp_instance_number,
       NULL            escp_end_date,
       MAX(host_name)  escp_value 
  FROM STATS$database_instance
 WHERE dbid = &&escp_this_dbid.
/

-- database version
SELECT 'DATABASE' escp_metric_group,
       'VERSION'  escp_metric_acronym,
       NULL       escp_instance_number,
       NULL       escp_end_date,
       version    escp_value 
  FROM v$instance
/

-- database platform_name
SELECT 'DATABASE'    escp_metric_group,
       'PLATFORM'    escp_metric_acronym,
       NULL          escp_instance_number,
       NULL          escp_end_date,
       '&&escp_platform.' escp_value 
  FROM DUAL
/

-- database db_block_size
SELECT 'DATABASE'           escp_metric_group,
       'DB_BLOCK_SIZE'      escp_metric_acronym,
       NULL                 escp_instance_number,
       NULL                 escp_end_date,
       SUBSTR(value, 1, 10) escp_value 
  FROM v$system_parameter2
 WHERE name = 'db_block_size'
/

-- database min_instance_host_id
SELECT 'DATABASE'                      escp_metric_group,
       'MIN_INST_HOST'                 escp_metric_acronym,
       TO_CHAR(MIN(instance_number)) escp_instance_number,
       NULL                            escp_end_date,
       MIN(host_name)                escp_value 
  FROM stats$database_instance 
 WHERE dbid = &&escp_this_dbid.
   AND instance_number IN (
SELECT MIN(instance_number) 
  FROM stats$database_instance 
 WHERE dbid = &&escp_this_dbid.)
/


---------------------------------------------------------------------------------------

-- instance instance_name
WITH
all_instances AS (
SELECT instance_number, MAX(startup_time) max_startup_time
  FROM stats$database_instance
 WHERE dbid = &&escp_this_dbid.
 GROUP BY 
       instance_number
)
SELECT 'INSTANCE'                 escp_metric_group,
       'INSTANCE_NAME'            escp_metric_acronym,
       TO_CHAR(h.instance_number) escp_instance_number,
       h.startup_time             escp_end_date,
       h.instance_name            escp_value
  FROM all_instances a,
       stats$database_instance h
 WHERE h.dbid = &&escp_this_dbid.
   AND h.instance_number = a.instance_number
   AND h.startup_time = a.max_startup_time
 ORDER BY
       h.instance_number
/

-- instance host_name
WITH
all_instances AS (
SELECT instance_number, MAX(startup_time) max_startup_time
  FROM stats$database_instance
 WHERE dbid = &&escp_this_dbid.
 GROUP BY 
       instance_number
)
SELECT 'INSTANCE'                 escp_metric_group,
       'HOST_NAME'                escp_metric_acronym,
       TO_CHAR(h.instance_number) escp_instance_number,
       h.startup_time             escp_end_date,
       h.host_name                escp_value
  FROM all_instances a,
       stats$database_instance h
 WHERE h.dbid = &&escp_this_dbid.
   AND h.instance_number = a.instance_number
   AND h.startup_time = a.max_startup_time
 ORDER BY
       h.instance_number
/

---------------------------------------------------------------------------------------

-- STATS$SYSSTAT 'CPU used by this session' CPU
WITH 
aas_on_cpu_per_hr as (
  SELECT 
    begin_time,
    end_time,
    dbid,
    snap_id,
    instance_number,
    ROUND(((end_time    -begin_time)*86400)) elap_time,
    (value              -last_value)/100 cpu_used_secs,
    DECODE( ROUND((value -last_value)/100 / ((end_time-begin_time)*86400)),0,0.1,  ROUND((value -last_value)/100 / ((end_time-begin_time)*86400),1)) aas_on_cpu
  FROM (
  SELECT 
    s.dbid,
    s.instance_number,
    s.startup_time ,
    s.snap_time end_time ,
    LAG(s.snap_time) OVER ( PARTITION BY s.dbid, s.instance_number, s.startup_time, e.name ORDER BY s.snap_id) AS begin_time ,
    e.name stat_name ,
    s.snap_id ,
    LAG(s.snap_id) OVER ( PARTITION BY s.dbid, s.instance_number, s.startup_time, e.name ORDER BY s.snap_id) AS last_snap_id,
    e.value ,
    LAG(e.value) OVER ( PARTITION BY s.dbid, s.instance_number, s.startup_time, e.name ORDER BY s.snap_id) AS last_value ,
    MIN(s.snap_time) OVER ( PARTITION BY s.dbid ) min_snap_time ,
    MAX(s.snap_time) OVER ( PARTITION BY s.dbid ) max_snap_time
  FROM perfstat.STATS$SNAPSHOT s
  INNER JOIN perfstat.STATS$SYSSTAT e --v$sysstat
  ON e.snap_id          = s.snap_id
  AND e.dbid            = s.dbid
  AND e.instance_number = s.instance_number
  AND e.name            ='CPU used by this session'
  AND s.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
  AND s.dbid = &&escp_this_dbid.
  AND s.snap_time BETWEEN TO_TIMESTAMP('&&escp_date_from.','&&escp_timestamp_format.') 
                      AND TO_TIMESTAMP('&&escp_date_to.','&&escp_timestamp_format.')
   )
  WHERE last_value IS NOT NULL
  ),
sample_timestamps as
(SELECT ROWNUM/8640  time_offset FROM DUAL CONNECT BY ROWNUM <= 359
  union all
 SELECT 0 time_offset FROM DUAL 
),
aas_on_cpu_per_10s as (
 SELECT instance_number,begin_time+time_offset sample_time , aas_on_cpu
   FROM aas_on_cpu_per_hr, sample_timestamps
  WHERE begin_time+time_offset<end_time
)
select 'CPU'                      escp_metric_group,
       'CPU'                      escp_metric_acronym,
       TO_CHAR(h.instance_number) escp_instance_number,
       h.sample_time              escp_end_date,
       TO_CHAR(h.aas_on_cpu)      escp_value
  from aas_on_cpu_per_10s h
order by instance_number,sample_time
/

-- STATS$SYSTEM_EVENT   resmgr:cpu quantum RMCPUQ 
WITH 
aas_on_cpurm_per_hr as (
  SELECT 
    begin_time,
    end_time,
    dbid,
    snap_id,
    instance_number,
    ROUND( ( (TIME_WAITED_MICRO-last_value) /1000000) /  ( (end_time-begin_time)*86400) ,1 )  aas_on_cpurm
  FROM (
  SELECT 
    s.dbid,
    s.instance_number,
    s.startup_time ,
    s.snap_time end_time , 
    LAG(s.snap_time) OVER ( PARTITION BY s.dbid, s.instance_number, s.startup_time ORDER BY s.snap_id) AS begin_time ,
    s.snap_id ,
    e.TIME_WAITED_MICRO,
    LAG(e.TIME_WAITED_MICRO) OVER ( PARTITION BY s.dbid, s.instance_number, s.startup_time ORDER BY s.snap_id) AS last_value 
  FROM perfstat.STATS$SNAPSHOT s
  INNER JOIN perfstat.STATS$SYSTEM_EVENT e --v$sysstat
  ON e.snap_id          = s.snap_id
  AND e.dbid            = s.dbid
  AND e.instance_number = s.instance_number
  AND e.event           ='resmgr:cpu quantum'
  AND s.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
  AND s.dbid = &&escp_this_dbid.
  AND s.snap_time BETWEEN TO_TIMESTAMP('&&escp_date_from.','&&escp_timestamp_format.') 
                      AND TO_TIMESTAMP('&&escp_date_to.','&&escp_timestamp_format.')
   )
  WHERE last_value IS NOT NULL 
  ),
sample_timestamps as
(SELECT ROWNUM/8640  time_offset FROM DUAL CONNECT BY ROWNUM <= 359
  union all
 SELECT 0 time_offset FROM DUAL 
),
aas_on_cpurm_per_10s as (
 SELECT instance_number,begin_time+time_offset sample_time , aas_on_cpurm
   FROM aas_on_cpurm_per_hr, sample_timestamps
  WHERE begin_time+time_offset<end_time
    AND aas_on_cpurm>0
)
select 'CPU'                      escp_metric_group,
       'RMCPUQ'                   escp_metric_acronym,
       TO_CHAR(h.instance_number) escp_instance_number,
       h.sample_time              escp_end_date,
       TO_CHAR(h.aas_on_cpurm)    escp_value 
  from aas_on_cpurm_per_10s h
order by instance_number,sample_time
/


-- stats$sga  MEM
WITH 
dba_hist_sga_sqf AS (
SELECT 
       h.snap_id,
       h.instance_number,
       SUM(h.value) value
  FROM stats$sga h
 WHERE h.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND h.dbid = &&escp_this_dbid.
 GROUP BY
       h.snap_id,
       h.instance_number
),
dba_hist_snapshot_sqf AS (
SELECT
       s.snap_id,
       s.instance_number,
       s.snap_time
  FROM stats$snapshot s
 WHERE s.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND s.dbid = &&escp_this_dbid.
   AND s.snap_time BETWEEN TO_TIMESTAMP('&&escp_date_from.','&&escp_timestamp_format.') 
              AND TO_TIMESTAMP('&&escp_date_to.','&&escp_timestamp_format.')
)
SELECT /*+ USE_HASH(h s) */
       'MEM'                      escp_metric_group,
       'SGA'                      escp_metric_acronym,
       TO_CHAR(h.instance_number) escp_instance_number,
       s.snap_time        escp_end_date,
       TO_CHAR(h.value)           escp_value
  FROM dba_hist_sga_sqf      h,
       dba_hist_snapshot_sqf s
 WHERE s.snap_id         = h.snap_id
   AND s.instance_number = h.instance_number
 ORDER BY
       h.instance_number,
       s.snap_id
/

-- stats$pgastat  MEM
WITH 
dba_hist_pgastat_sqf AS (
SELECT 
       h.snap_id,
       h.instance_number,
       h.value
  FROM stats$pgastat h
 WHERE h.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND h.dbid = &&escp_this_dbid.
   AND h.name = 'total PGA allocated'
),
dba_hist_snapshot_sqf AS (
SELECT 
       s.snap_id,
       s.instance_number,
       s.snap_time
  FROM stats$snapshot s
 WHERE s.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND s.dbid = &&escp_this_dbid.
   AND s.snap_time BETWEEN TO_TIMESTAMP('&&escp_date_from.','&&escp_timestamp_format.') 
              AND TO_TIMESTAMP('&&escp_date_to.','&&escp_timestamp_format.')
)
SELECT /*+ USE_HASH(h s) */
       'MEM'                      escp_metric_group,
       'PGA'                      escp_metric_acronym,
       TO_CHAR(h.instance_number) escp_instance_number,
       s.snap_time        escp_end_date,
       TO_CHAR(h.value)           escp_value
  FROM dba_hist_pgastat_sqf  h,
       dba_hist_snapshot_sqf s
 WHERE s.snap_id         = h.snap_id
   AND s.instance_number = h.instance_number
 ORDER BY
       h.instance_number,
       s.snap_time
/

-- Statspack does not collect a series of tablespace usage 
-- The current utilization it is just iterated across all snaps
WITH
dba_hist_snapshot_sqf AS (
SELECT
       s.snap_id,
       s.snap_time
  FROM stats$snapshot s
 WHERE s.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND s.dbid = &&escp_this_dbid.
   AND s.instance_number = &&escp_this_inst_num.
   AND s.snap_time BETWEEN TO_TIMESTAMP('&&escp_date_from.','&&escp_timestamp_format.') 
              AND TO_TIMESTAMP('&&escp_date_to.','&&escp_timestamp_format.')
)
select 'DISK'                                         escp_metric_group,
       SUBSTR(t.contents, 1, 4)                       escp_metric_acronym,
       NULL                                           escp_instance_number,
       s.snap_time                            escp_end_date,
       TO_CHAR(sum(bytes))                    escp_value
  from dba_data_files d,dba_tablespaces t,dba_hist_snapshot_sqf s
 where d.tablespace_name=t.tablespace_name
 GROUP BY
       t.contents,
       s.snap_time
 UNION ALL 
Select 'DISK'                       escp_metric_group,
       'TEMP'                       escp_metric_acronym,
       NULL                         escp_instance_number,
       s.snap_time                  escp_end_date,
       TO_CHAR(sum(bytes))          escp_value
  from dba_temp_files f, dba_hist_snapshot_sqf s
 GROUP BY
       s.snap_time
 UNION ALL 
Select 'DISK'                       escp_metric_group,
       'LOG'                        escp_metric_acronym,
       NULL                         escp_instance_number,
       s.snap_time                  escp_end_date,
       TO_CHAR(sum(bytes))          escp_value
  from v$log f, dba_hist_snapshot_sqf s
 GROUP BY
       s.snap_time
 ORDER BY
       escp_metric_acronym,
       escp_end_date
/


-- stats$sysstat IOPS MBPS NETW IC
WITH
dba_hist_sysstat_sqf AS (
SELECT 
       h.snap_id,
       h.instance_number,
       h.name stat_name,
       h.value
  FROM stats$sysstat h
 WHERE h.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND h.dbid = &&escp_this_dbid.
   AND h.name IN (
       'physical read total IO requests',
       'physical write total IO requests',
       'redo writes',
       'physical read total bytes',
       'physical write total bytes',
       'redo size',
       'physical reads',
       'physical reads direct',
       'physical reads cache',
       'physical writes',
       'physical writes direct',
       'physical writes from cache',
       'bytes sent via SQL*Net to client',
       'bytes received via SQL*Net from client',
       'bytes sent via SQL*Net to dblink',
       'bytes received via SQL*Net from dblink',
       'gc cr blocks received',
       'gc current blocks received',
       'gc cr blocks served',
       'gc current blocks served',
       'gcs messages sent',
       'ges messages sent'
       )
),
dba_hist_snapshot_sqf AS (
SELECT
       s.snap_id,
       s.instance_number,
       s.snap_time
  FROM stats$snapshot s
 WHERE s.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND s.dbid = &&escp_this_dbid.
   AND s.snap_time BETWEEN TO_TIMESTAMP('&&escp_date_from.','&&escp_timestamp_format.') 
              AND TO_TIMESTAMP('&&escp_date_to.','&&escp_timestamp_format.')
)
SELECT /*+ USE_HASH(h s) */
       CASE h.stat_name
       WHEN 'physical read total IO requests'        THEN 'IOPS'
       WHEN 'physical write total IO requests'       THEN 'IOPS'
       WHEN 'redo writes'                            THEN 'IOPS'
       WHEN 'physical read total bytes'              THEN 'MBPS'
       WHEN 'physical write total bytes'             THEN 'MBPS'
       WHEN 'redo size'                              THEN 'MBPS'
       WHEN 'physical reads'                         THEN 'PHYR'
       WHEN 'physical reads direct'                  THEN 'PHYR'
       WHEN 'physical reads cache'                   THEN 'PHYR'
       WHEN 'physical writes'                        THEN 'PHYW'
       WHEN 'physical writes direct'                 THEN 'PHYW'
       WHEN 'physical writes from cache'             THEN 'PHYW'
       WHEN 'bytes sent via SQL*Net to client'       THEN 'NETW'
       WHEN 'bytes received via SQL*Net from client' THEN 'NETW'
       WHEN 'bytes sent via SQL*Net to dblink'       THEN 'NETW'
       WHEN 'bytes received via SQL*Net from dblink' THEN 'NETW'
       WHEN 'gc cr blocks received'                  THEN 'IC'
       WHEN 'gc current blocks received'             THEN 'IC'
       WHEN 'gc cr blocks served'                    THEN 'IC'
       WHEN 'gc current blocks served'               THEN 'IC'
       WHEN 'gcs messages sent'                      THEN 'IC'
       WHEN 'ges messages sent'                      THEN 'IC'
       END                                           escp_metric_group,
       CASE h.stat_name
       WHEN 'physical read total IO requests'        THEN 'RREQS'
       WHEN 'physical write total IO requests'       THEN 'WREQS'
       WHEN 'redo writes'                            THEN 'WREDO'
       WHEN 'physical read total bytes'              THEN 'RBYTES'
       WHEN 'physical write total bytes'             THEN 'WBYTES'
       WHEN 'redo size'                              THEN 'WREDOBYTES'
       WHEN 'physical reads'                         THEN 'PHYR'
       WHEN 'physical reads direct'                  THEN 'PHYRD'
       WHEN 'physical reads cache'                   THEN 'PHYRC'
       WHEN 'physical writes'                        THEN 'PHYW'
       WHEN 'physical writes direct'                 THEN 'PHYWD'
       WHEN 'physical writes from cache'             THEN 'PHYWC'
       WHEN 'bytes sent via SQL*Net to client'       THEN 'TOCLIENT'
       WHEN 'bytes received via SQL*Net from client' THEN 'FROMCLIENT'
       WHEN 'bytes sent via SQL*Net to dblink'       THEN 'TODBLINK'
       WHEN 'bytes received via SQL*Net from dblink' THEN 'FROMDBLINK'
       WHEN 'gc cr blocks received'                  THEN 'GCCRBR'
       WHEN 'gc current blocks received'             THEN 'GCCBLR'
       WHEN 'gc cr blocks served'                    THEN 'GCCRBS'
       WHEN 'gc current blocks served'               THEN 'GCCBLS'
       WHEN 'gcs messages sent'                      THEN 'GCSMS'
       WHEN 'ges messages sent'                      THEN 'GESMS'
       END                                           escp_metric_acronym,
       TO_CHAR(h.instance_number)                    escp_instance_number,
       s.snap_time                           escp_end_date,
       TO_CHAR(h.value)                              escp_value
  FROM dba_hist_sysstat_sqf  h,
       dba_hist_snapshot_sqf s
 WHERE s.snap_id         = h.snap_id
   AND s.instance_number = h.instance_number
 ORDER BY
       CASE h.stat_name
       WHEN 'physical read total IO requests'        THEN 1.1
       WHEN 'physical write total IO requests'       THEN 1.2
       WHEN 'redo writes'                            THEN 1.3
       WHEN 'physical read total bytes'              THEN 2.1
       WHEN 'physical write total bytes'             THEN 2.2
       WHEN 'redo size'                              THEN 2.3
       WHEN 'physical reads'                         THEN 3.1
       WHEN 'physical reads direct'                  THEN 3.2
       WHEN 'physical reads cache'                   THEN 3.3
       WHEN 'physical writes'                        THEN 4.1
       WHEN 'physical writes direct'                 THEN 4.2
       WHEN 'physical writes from cache'             THEN 4.3
       WHEN 'bytes sent via SQL*Net to client'       THEN 5.1
       WHEN 'bytes received via SQL*Net from client' THEN 5.2
       WHEN 'bytes sent via SQL*Net to dblink'       THEN 5.3
       WHEN 'bytes received via SQL*Net from dblink' THEN 5.4
       WHEN 'gc cr blocks received'                  THEN 6.1
       WHEN 'gc current blocks received'             THEN 6.2
       WHEN 'gc cr blocks served'                    THEN 6.3
       WHEN 'gc current blocks served'               THEN 6.4
       WHEN 'gcs messages sent'                      THEN 6.5
       WHEN 'ges messages sent'                      THEN 6.6
       ELSE 9.9 
       END,
       h.instance_number,
       s.snap_time
/

-- STATS$DLM_MISC IC
WITH 
dba_hist_dlm_misc_sqf AS (
SELECT 
       h.snap_id,
       h.instance_number,
       h.name,
       h.value
  FROM STATS$DLM_MISC h
 WHERE h.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND h.dbid = &&escp_this_dbid.
   AND h.name IN (
       'gcs msgs received',
       'ges msgs received'
       )
),
dba_hist_snapshot_sqf AS (
SELECT 
       s.snap_id,
       s.instance_number,
       s.snap_time
  FROM stats$snapshot s
 WHERE s.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND s.dbid = &&escp_this_dbid.
   AND s.snap_time BETWEEN TO_TIMESTAMP('&&escp_date_from.','&&escp_timestamp_format.') 
              AND TO_TIMESTAMP('&&escp_date_to.','&&escp_timestamp_format.')
)
SELECT /*+ USE_HASH(h s) */
       'IC'                       escp_metric_group,
       CASE h.name
       WHEN 'gcs msgs received' THEN 'GCSMR'
       WHEN 'ges msgs received' THEN 'GESMR'
       END                        escp_metric_acronym,
       TO_CHAR(h.instance_number) escp_instance_number,
       s.snap_time        escp_end_date,
       TO_CHAR(h.value)           escp_value
  FROM dba_hist_dlm_misc_sqf h,
       dba_hist_snapshot_sqf s
 WHERE s.snap_id         = h.snap_id
   AND s.instance_number = h.instance_number
 ORDER BY
       CASE h.name
       WHEN 'gcs msgs received' THEN 1
       WHEN 'ges msgs received' THEN 2
       ELSE 9 
       END,
       h.instance_number,
       s.snap_time
/

-- stats$osstat  OS
WITH
dba_hist_osstat_sqf AS (
SELECT 
       h.snap_id,
       h.instance_number,
       n.stat_name,
       h.value
  FROM stats$osstat h, STATS$OSSTATNAME n
 WHERE h.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND h.dbid = &&escp_this_dbid.
   AND h.OSSTAT_ID=n.OSSTAT_ID
   AND n.stat_name IN (
       'LOAD', 
       'NUM_CPUS', 
       'NUM_CPU_CORES', 
       'PHYSICAL_MEMORY_BYTES',
       'IDLE_TIME',
       'BUSY_TIME',
       'USER_TIME',
       'SYS_TIME',
       'IOWAIT_TIME',
       'NICE_TIME', 
       'OS_CPU_WAIT_TIME', 
       'RSRC_MGR_CPU_WAIT_TIME'
       )
),
dba_hist_snapshot_sqf AS (
SELECT 
       s.snap_id,
       s.instance_number,
       s.snap_time
  FROM stats$snapshot s
 WHERE s.snap_id BETWEEN &&escp_minimum_snap_id. AND &&escp_maximum_snap_id.
   AND s.dbid = &&escp_this_dbid.
   AND s.snap_time BETWEEN TO_TIMESTAMP('&&escp_date_from.','&&escp_timestamp_format.') 
              AND TO_TIMESTAMP('&&escp_date_to.','&&escp_timestamp_format.')
)
SELECT /*+ USE_HASH(h s) */
      'OS'                           escp_metric_group,
       CASE h.stat_name
       WHEN 'LOAD'                   THEN 'OSLOAD'
       WHEN 'NUM_CPUS'               THEN 'OSCPUS'
       WHEN 'NUM_CPU_CORES'          THEN 'OSCORES'
       WHEN 'PHYSICAL_MEMORY_BYTES'  THEN 'OSMEMBYTES'
       WHEN 'IDLE_TIME'              THEN 'OSIDLE'
       WHEN 'BUSY_TIME'              THEN 'OSBUSY'
       WHEN 'USER_TIME'              THEN 'OSUSER'
       WHEN 'SYS_TIME'               THEN 'OSSYS'
       WHEN 'IOWAIT_TIME'            THEN 'OSIOWAIT'
       WHEN 'NICE_TIME'              THEN 'OSNICEWAIT'
       WHEN 'OS_CPU_WAIT_TIME'       THEN 'OSCPUWAIT'
       WHEN 'RSRC_MGR_CPU_WAIT_TIME' THEN 'RMCPUWAIT'
       END                           escp_metric_acronym,
       TO_CHAR(h.instance_number)    escp_instance_number,
       s.snap_time           escp_end_date,
       TO_CHAR(h.value)              escp_value
  FROM dba_hist_osstat_sqf   h,
       dba_hist_snapshot_sqf s
 WHERE s.snap_id         = h.snap_id
   AND s.instance_number = h.instance_number
 ORDER BY
       CASE h.stat_name
       WHEN 'LOAD'                   THEN 01
       WHEN 'NUM_CPUS'               THEN 02
       WHEN 'NUM_CPU_CORES'          THEN 03
       WHEN 'PHYSICAL_MEMORY_BYTES'  THEN 04
       WHEN 'IDLE_TIME'              THEN 05
       WHEN 'BUSY_TIME'              THEN 06
       WHEN 'USER_TIME'              THEN 07
       WHEN 'SYS_TIME'               THEN 08
       WHEN 'IOWAIT_TIME'            THEN 09
       WHEN 'NICE_TIME'              THEN 10
       WHEN 'OS_CPU_WAIT_TIME'       THEN 11
       WHEN 'RSRC_MGR_CPU_WAIT_TIME' THEN 12
       ELSE 99 
       END,
       h.instance_number,
       s.snap_time
/   

---------------------------------------------------------------------------------------
SELECT 'PRODUCT'                   escp_metric_group,
       'PRODUCT'                   escp_metric_acronym,
       TO_CHAR(nvl2(con_id,decode(con_id,-1,0,con_id),0))   escp_instance_number,
       LAST_USAGE_DATE          escp_end_date,
       PRODUCT                  escp_value
from (
@@escp_products.sql
)
where last_usage_date is not null
order by TO_CHAR(NVL(CON_ID,0)),last_usage_date
/
---------------------------------------------------------------------------------------

-- collection end
SELECT 'END'                      escp_metric_group,
       d.name                     escp_metric_acronym,
       to_char('&&escp_con_id.')  escp_instance_number,
       SYSDATE                    escp_end_date,
       i.host_name                escp_value 
  FROM v$instance i, 
       v$database d
/

SPO OFF;
SET TERM ON ECHO OFF FEED ON VER ON HEA ON PAGES 14 COLSEP ' ' LIN 80 TRIMS OFF TRIM ON TI OFF TIMI OFF ARRAY 15 NUM 10 SQLBL OFF BLO ON RECSEP WR;
