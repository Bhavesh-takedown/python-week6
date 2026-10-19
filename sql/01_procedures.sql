CREATE OR REPLACE FUNCTION etl.audit_customer_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO dw.customer_change_audit (customer_sk, customer_id, action)
    VALUES (NEW.customer_sk, NEW.customer_id, 'INSERT');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS customer_dim_insert_audit ON dw.customer_dim;
CREATE TRIGGER customer_dim_insert_audit
AFTER INSERT ON dw.customer_dim
FOR EACH ROW
EXECUTE FUNCTION etl.audit_customer_insert();

CREATE OR REPLACE PROCEDURE etl.load_customer_dimension()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Serialize loads so two batches cannot create concurrent current versions.
    PERFORM pg_advisory_xact_lock(hashtextextended('etl.load_customer_dimension', 0));

    IF EXISTS (
        SELECT 1
        FROM raw.customer_stage AS s
        JOIN dw.customer_dim AS d USING (customer_id)
        WHERE d.is_current
          AND (d.full_name, d.email, d.segment, d.city, d.profile)
              IS DISTINCT FROM (s.full_name, s.email, s.segment, s.city, s.profile)
          AND s.source_updated_at <= d.valid_from
    ) THEN
        RAISE EXCEPTION 'Customer batch contains a changed row with a stale source_updated_at';
    END IF;

    -- Close changed versions. valid_to is exclusive and meets the new valid_from.
    UPDATE dw.customer_dim AS d
       SET valid_to = s.source_updated_at,
           is_current = false
      FROM raw.customer_stage AS s
     WHERE d.customer_id = s.customer_id
       AND d.is_current
       AND (d.full_name, d.email, d.segment, d.city, d.profile)
           IS DISTINCT FROM (s.full_name, s.email, s.segment, s.city, s.profile);

    -- Unchanged rows still match and are left alone; new and just-closed keys insert.
    MERGE INTO dw.customer_dim AS target
    USING raw.customer_stage AS source
       ON target.customer_id = source.customer_id
      AND target.is_current
    WHEN NOT MATCHED THEN
        INSERT (customer_id, full_name, email, segment, city, profile,
                valid_from, valid_to, is_current)
        VALUES (source.customer_id, source.full_name, source.email,
                source.segment, source.city, source.profile,
                source.source_updated_at, 'infinity'::timestamptz, true);
END;
$$;

CREATE OR REPLACE PROCEDURE etl.load_sales()
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM raw.sales_stage AS s
        WHERE NOT EXISTS (
            SELECT 1
            FROM dw.customer_dim AS d
            WHERE d.customer_id = s.customer_id
              AND s.event_ts >= d.valid_from
              AND s.event_ts < d.valid_to
        )
    ) THEN
        RAISE EXCEPTION 'Sales batch contains a row without a customer version valid at event_ts';
    END IF;

    INSERT INTO dw.fact_sales (
        event_date, event_ts, sale_id, customer_sk, product_id,
        quantity, unit_price, total_amount, sale_payload
    )
    SELECT s.event_date,
           s.event_ts,
           s.sale_id,
           d.customer_sk,
           s.product_id,
           s.quantity,
           s.unit_price,
           s.quantity * s.unit_price,
           s.sale_payload
    FROM raw.sales_stage AS s
    JOIN dw.customer_dim AS d
      ON d.customer_id = s.customer_id
     AND s.event_ts >= d.valid_from
     AND s.event_ts < d.valid_to
    ON CONFLICT (sale_id, event_date) DO UPDATE
       SET event_ts = EXCLUDED.event_ts,
           customer_sk = EXCLUDED.customer_sk,
           product_id = EXCLUDED.product_id,
           quantity = EXCLUDED.quantity,
           unit_price = EXCLUDED.unit_price,
           total_amount = EXCLUDED.total_amount,
           sale_payload = EXCLUDED.sale_payload;
END;
$$;
