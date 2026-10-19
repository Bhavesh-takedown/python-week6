-- Two existing customer versions. The partial unique index makes this seed repeatable.
INSERT INTO dw.customer_dim (
    customer_id, full_name, email, segment, city, profile,
    valid_from, valid_to, is_current
)
VALUES
    ('C001', 'Alice Kim', 'alice@example.com', 'Silver', 'Chennai',
     '{"loyalty_tier": "silver", "interests": ["books"]}'::jsonb,
     '2025-01-01T00:00:00Z', 'infinity'::timestamptz, true),
    ('C002', 'Bob Rao', 'bob@example.com', 'Silver', 'Pune',
     '{"loyalty_tier": "silver", "interests": ["music"]}'::jsonb,
     '2025-01-01T00:00:00Z', 'infinity'::timestamptz, true)
ON CONFLICT (customer_id) WHERE is_current DO NOTHING;
