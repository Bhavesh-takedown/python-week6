-- Date predicates enable partition pruning. Compare actual rows, loops, buffers,
-- and planning/execution time on a larger data set before changing indexes.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT f.event_date,
       d.segment,
       SUM(f.total_amount) AS revenue
FROM dw.fact_sales AS f
JOIN dw.customer_dim AS d USING (customer_sk)
WHERE f.event_date >= DATE '2026-01-01'
  AND f.event_date < DATE '2026-02-01'
GROUP BY f.event_date, d.segment
ORDER BY f.event_date, d.segment;
