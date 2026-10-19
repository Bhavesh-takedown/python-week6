# Week 6 — Advanced SQL for Data Engineering

A runnable PostgreSQL mini project for loading a customer dimension and a partitioned sales fact table. It demonstrates a client-side `\copy` load, SCD Type 2 processing with `MERGE`, idempotent fact upserts, JSONB queries, indexes, an audit trigger, and `EXPLAIN ANALYZE`.

## Requirements

- PostgreSQL 15 or later (`MERGE` was added in PostgreSQL 15)
- `psql`
- A database where you can create schemas and tables

## Run the pipeline

Run from this project directory so the relative CSV paths in the psql script resolve correctly:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/run_pipeline.psql
```

In PowerShell, set the connection string and run:

```powershell
$env:DATABASE_URL = "postgresql://USER:PASSWORD@HOST:5432/DATABASE"
psql $env:DATABASE_URL -v ON_ERROR_STOP=1 -f sql/run_pipeline.psql
```

The pipeline creates schemas and tables, seeds two pre-existing customers, clears only the raw staging tables, loads the sample CSVs with psql `\copy`, applies customer history changes, loads sales, runs `ANALYZE`, and prints a sample execution plan. The seed and fact load are safe to rerun with the included sample data. Use a disposable development database for practice.

`\copy` is a psql command that reads files from the client machine running `psql`. SQL `COPY FROM '/path'` reads a file from the database server machine and usually needs elevated server-side file permissions. This project uses `\copy` so the CSVs can live alongside the project.

## What the pipeline does

1. Loads one customer update per business key into `raw.customer_stage` and sales into `raw.sales_stage`.
2. `CALL etl.load_customer_dimension()` closes the active SCD Type 2 row when tracked attributes change, then uses `MERGE` to insert a new version for changed or new customers. The old row's `valid_to` equals the new row's `valid_from`; intervals are half-open.
3. `CALL etl.load_sales()` resolves each sale to the customer version valid at its event timestamp, then inserts or updates by `(sale_id, event_date)`.
4. An insert trigger writes dimension version inserts to `dw.customer_change_audit`.
5. The fact table is range partitioned by `event_date`; the execution-plan example filters on a date range so PostgreSQL can prune partitions.

## Try these queries

```sql
-- Type 2 history for a business key
SELECT customer_id, full_name, city, segment, valid_from, valid_to, is_current
FROM dw.customer_dim
WHERE customer_id = 'C001'
ORDER BY valid_from;

-- JSONB field and containment queries
SELECT customer_id, profile ->> 'loyalty_tier' AS loyalty_tier
FROM dw.customer_dim
WHERE is_current;

SELECT customer_id
FROM dw.customer_dim
WHERE profile @> '{"interests": ["travel"]}'::jsonb;

-- Composite index candidate: equality on customer, then a bounded date range
EXPLAIN (ANALYZE, BUFFERS)
SELECT sale_id, event_ts, total_amount
FROM dw.fact_sales
WHERE customer_sk = 1
  AND event_date >= DATE '2026-01-01'
  AND event_date < DATE '2026-02-01';

-- Trigger audit trail
SELECT customer_id, action, changed_at
FROM dw.customer_change_audit
ORDER BY audit_id;
```

The surrogate key in the index example is database-generated; replace `1` with a key from `dw.customer_dim`. A tiny sample may favor a sequential scan. `EXPLAIN ANALYZE` reports what happened for this database and data size, not a promise that an index will always be chosen.

## Concepts covered

- **DML:** `INSERT`, `UPDATE`, `DELETE`, `MERGE`, and `ON CONFLICT` upsert
- **Partitioning:** range partitions and a default partition
- **Bulk loading:** psql `\copy` from CSV
- **Optimization:** `EXPLAIN (ANALYZE, BUFFERS)`, `ANALYZE`, composite and partial indexes
- **Transactions:** the customer procedure's update and merge run atomically inside the calling transaction; an advisory transaction lock serializes dimension loads
- **Isolation:** PostgreSQL defaults to `READ COMMITTED`. `REPEATABLE READ` gives a transaction a stable snapshot; `SERIALIZABLE` detects some concurrent anomalies and may require retrying the transaction
- **Stored procedures and triggers:** `CALL etl.load_customer_dimension()` and the dimension insert audit trigger
- **Warehouse modeling:** a customer dimension with SCD Type 2 history and a date-partitioned sales fact table
- **SCD variants:** Type 1 overwrites the current value, Type 2 adds effective-dated versions, and Type 3 keeps a limited previous value in another column. This project implements Type 2.
- **JSON:** JSONB extraction and containment; a GIN index is available for containment-heavy profile searches

The sample is for teaching. Production pipelines also need batch identifiers, rejected-row handling, access control, monitoring, schema evolution, and a late-arriving-dimension policy.

## Assessment

See [assessment.md](assessment.md) for the 40-minute test and [answer-key.md](answer-key.md) for worked answers. Give learners only the assessment file during the test.
