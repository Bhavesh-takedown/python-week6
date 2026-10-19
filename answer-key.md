# Week 6 assessment — answer key

## 1. Predict the output

`P-10` matches, so its quantity is updated from 5 to 8. `P-20` has no target match, so it is inserted with quantity 3. Final rows:

| product_id | quantity |
|---|---:|
| P-10 | 8 |
| P-20 | 3 |

One row is updated and one row is inserted. The statement has no `WHEN NOT MATCHED BY SOURCE` clause, so a target-only row remains unchanged.

## 2. DML scenario

One valid solution, assuming the incoming row is already stored in `raw.customer_stage` and includes `source_updated_at = '2026-04-01'`:

```sql
BEGIN;

SELECT pg_advisory_xact_lock(hashtextextended('etl.load_customer_dimension', 0));

UPDATE dw.customer_dim AS d
   SET valid_to = s.source_updated_at,
       is_current = false
  FROM raw.customer_stage AS s
 WHERE d.customer_id = s.customer_id
   AND d.is_current
   AND (d.city) IS DISTINCT FROM (s.city);

MERGE INTO dw.customer_dim AS target
USING raw.customer_stage AS source
   ON target.customer_id = source.customer_id
  AND target.is_current
WHEN NOT MATCHED THEN
    INSERT (customer_id, city, valid_from, valid_to, is_current)
    VALUES (source.customer_id, source.city, source.source_updated_at,
            'infinity'::timestamptz, true);

COMMIT;
```

The old version is valid on `[2025-03-01, 2026-04-01)`; the new one is valid from `2026-04-01`. A partial unique index on `customer_id WHERE is_current` enforces one current row per business key. The transaction makes both DML steps commit or roll back together. A transaction-scoped advisory lock serializes competing dimension loads; a production design can also use suitable row locks and retry handling.

## 3. Optimization

Investigate:

1. Keep the half-open date predicates on the partition key, as shown, and check that the plan scans only the partition containing January 2026. With partition pruning working, yearly partitions outside the date range should be absent from the plan.
2. Create or retain a composite index matching equality on `customer_sk` followed by the date range:

   ```sql
   CREATE INDEX fact_sales_customer_date_idx
       ON dw.fact_sales (customer_sk, event_date);
   ```

   On a partitioned table, PostgreSQL creates a partitioned index with corresponding child indexes. Compare actual rows, rows removed by filter, buffer reads, and execution time. Refresh statistics with `ANALYZE` after a substantial load.

An index is not guaranteed to win for a tiny table or a query that reads a large share of a partition. The measured plan and workload determine whether it helps.
