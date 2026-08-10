# Step 15 — Official 500k Benchmark Runbook

Run from the repository root. The rebuild deletes only
`CampusSpaceManagementSystem`; allow no concurrent writes during Step 15.

## 1. Prepare the runner

```bash
docker ps --filter name=sqlserver2022
read -rsp "SQL Server SA password: " G09_SQL_PASSWORD
echo
```

Define a helper that preserves SQL Server output even when `sqlcmd` fails:

```bash
run_sql () {
  local script_path="$1" output_name="$2"
  local remote_script="/tmp/g09-step15-script.sql" remote_output="/tmp/$output_name"
  local local_output="outputs/15-index-tuning-report-G09/$output_name"
  local sql_status copy_status
  docker cp "$script_path" "sqlserver2022:$remote_script" || return $?
  docker exec sqlserver2022 /bin/rm -f "$remote_output" || return $?
  docker exec -e SQLCMDPASSWORD="$G09_SQL_PASSWORD" sqlserver2022 \
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -y 0 \
    -i "$remote_script" -o "$remote_output"
  sql_status=$?
  docker cp "sqlserver2022:$remote_output" "$local_output"
  copy_status=$?
  [ "$copy_status" -eq 0 ] || return "$copy_status"
  return "$sql_status"
}
```

## 2. Rebuild the database

```bash
docker exec -e SQLCMDPASSWORD="$G09_SQL_PASSWORD" sqlserver2022 \
  /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -d master \
  -Q "IF DB_ID('CampusSpaceManagementSystem') IS NOT NULL
      BEGIN
        ALTER DATABASE CampusSpaceManagementSystem SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE CampusSpaceManagementSystem;
      END;"
```

Run these one at a time, in order, and stop if any command returns nonzero:

```bash
run_sql outputs/05-db-definition-G09.sql step05-output.txt
run_sql outputs/06-sample-data-G09.sql step06-output.txt
run_sql outputs/10-schema-migration-G09.sql step10-output.txt
run_sql outputs/12-concurrency-implementation-G09.sql step12-output.txt
run_sql outputs/14-data-generator-G09/high-volume-sample-data-G09.sql step14-output-500k.txt
run_sql outputs/16-analytical-queries-G09.sql step16-output-500k.txt
```

## 3. Verify the rebuilt state

```bash
docker exec -e SQLCMDPASSWORD="$G09_SQL_PASSWORD" sqlserver2022 \
  /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -y 0 \
  -Q "SET NOCOUNT ON; USE CampusSpaceManagementSystem;
      SELECT COUNT_BIG(*) AS generated_bookings FROM dbo.BOOKING AS B
      JOIN dbo.gen_user_marker AS GM ON GM.user_id = B.requester_id;
      SELECT COL_LENGTH('dbo.FACILITY', 'space_code') AS facility_space_code_column,
             OBJECT_ID('dbo.SPACE_FACILITY', 'U') AS obsolete_space_facility,
             TYPE_ID('dbo.FacilityListType') AS facility_list_type, OBJECT_ID('dbo.fn_GetAvailableSpaces', 'IF') AS w2_function,
             OBJECT_ID('dbo.fn_CountApprovedBookingHourBySemester', 'IF') AS w3_function, OBJECT_ID('dbo.fn_CountApprovedBookingByWeekdayHourAndHourWithGivenSemester', 'IF') AS w4_function;"
```

Require exactly `500000` generated bookings, non-`NULL` IDs for the migrated
column and Step 16 objects, and `obsolete_space_facility = NULL`.

## 4. Run validation only

Keep this gate in `outputs/15-index-tuning-benchmark-G09.sql`:

```sql
DECLARE @ExecuteFullBenchmark BIT = 0;
```

```bash
run_sql outputs/15-index-tuning-benchmark-G09.sql step15-validation-500k.txt
rg -n "Dataset preflight passed|Canonical workload compilation and deterministic parameter validation passed|VALIDATION ONLY COMPLETE" \
  outputs/15-index-tuning-report-G09/step15-validation-500k.txt
```

Proceed only when `run_sql` returns zero and output includes exactly
`VALIDATION ONLY COMPLETE. Set @ExecuteFullBenchmark = 1 for the controlled full run.`

## 5. Run the official benchmark

Change the gate to `1`, keep concurrent writes stopped, then run:

```bash
run_sql outputs/15-index-tuning-benchmark-G09.sql step15-benchmark-output-500k.txt
rg -n "CLEAN BASE READY|INDEXED CANDIDATE SET READY|Benchmark complete|Original candidate index existence and enabled/disabled state verified" \
  outputs/15-index-tuning-report-G09/step15-benchmark-output-500k.txt
rg -c "^(BASE|INDEXED) W[1-4] run [1-5]$" \
  outputs/15-index-tuning-report-G09/step15-benchmark-output-500k.txt
```

Require `CLEAN BASE READY.`, `INDEXED CANDIDATE SET READY.`, a measured-run
count of `40`, and final markers `Benchmark complete.` and
`Original candidate index existence and enabled/disabled state verified.`

The benchmark snapshots and restores the tested candidate-index state. Do not
accept a run without the final restoration marker. Return the gate to `0` after
the run.

## 6. Preserve official evidence

Raw evidence: `outputs/15-index-tuning-report-G09/step15-benchmark-output-500k.txt`.
Final report: `outputs/15-index-tuning-report-G09.md`; it must use only this
official 500k run as measurement evidence.

```bash
unset G09_SQL_PASSWORD
```
