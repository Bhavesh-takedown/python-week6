# Week 6 assessment — 40 minutes

**Total: 30 points.** Suggested timing: Question 1, 10 minutes; Question 2, 15 minutes; Question 3, 15 minutes. Show SQL where requested and state any assumptions.

## 1. Predict the output — 8 points, 10 minutes

Starting rows:

| product_id | quantity |
|---|---:|
| P-10 | 5 |

Staging rows:

| product_id | quantity |
|---|---:|
| P-10 | 8 |
| P-20 | 3 |

The following statement runs:

```sql
MERGE INTO inventory AS target
USING inventory_stage AS source
   ON target.product_id = source.product_id
WHEN MATCHED THEN
    UPDATE SET quantity = source.quantity
WHEN NOT MATCHED THEN
    INSERT (product_id, quantity)
    VALUES (source.product_id, source.quantity);
```

What rows are in `inventory` afterward? How many rows were updated and inserted? What would happen to a target row whose key is absent from the staging table?

## 2. DML scenario — 12 points, 15 minutes

`dw.customer_dim` stores effective dated versions using `customer_id`, `city`, `valid_from`, `valid_to`, and `is_current`. The active row for `C010` says `Delhi`, starting `2025-03-01`. A batch arrives with `Mumbai`, effective `2026-04-01`.

Write a transaction that closes the old version and uses `MERGE` to insert a new current version. Treat `valid_to` as exclusive. State one constraint or concurrency safeguard that prevents two current rows for the same customer. Explain how the transaction keeps the close and insert atomic.

## 3. Optimization — 10 points, 15 minutes

A query scans `dw.fact_sales` for January 2026 and one customer:

```sql
SELECT sale_id, event_ts, total_amount
FROM dw.fact_sales
WHERE customer_sk = 42
  AND event_date >= DATE '2026-01-01'
  AND event_date < DATE '2026-02-01';
```

The fact table is range partitioned by `event_date`. `EXPLAIN ANALYZE` shows several yearly partitions being scanned and many rows discarded. Name two changes you would investigate, including one SQL or index change. Describe what evidence in a new execution plan would show whether your changes helped.
