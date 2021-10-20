CREATE OR REPLACE FUNCTION create_staging_table(staging_table VARCHAR, _table VARCHAR)
    RETURNS VOID AS $$
    DECLARE
        next_val INT;
        staging_def TEXT;
        seq_name VARCHAR;
    BEGIN
        RAISE NOTICE 'Creating staging table: %s', staging_table;
        EXECUTE format('
        DROP TABLE IF EXISTS %1$s;
        CREATE TABLE %1$s (LIKE %2$s INCLUDING ALL)', staging_table, _table);

        RAISE NOTICE 'Setting staging identity columns to respective target identity columns next value';
        EXECUTE format('
        CREATE TABLE res AS
            SELECT 
                inc, 
                target_seq,
                staging_seq
            FROM (
                SELECT seqrelid, seqincrement AS inc 
                FROM pg_sequence
            ) seq
            JOIN (
                SELECT 
                    attname,
                    pg_get_serial_sequence(''%1$s'', attname) AS target_seq,
                    pg_get_serial_sequence(''%2$I'', attname) AS staging_seq,
                    pg_get_serial_sequence(''%1$s'', attname)::regclass::oid AS seq_oid
                FROM pg_attribute
                WHERE attrelid = ''%1$I''::regclass
                AND pg_get_serial_sequence(''%1$s'', attname) IS NOT NULL
                AND attidentity != ''''
            ) attr
            ON (seq.seqrelid = attr.seq_oid)
        ', _table, staging_table);

        FOR seq_name IN (SELECT target_seq FROM res)
        LOOP
            RAISE NOTICE 'Sequence table: %', seq_name;
            EXECUTE format('
            SELECT
               CASE
                    WHEN seq.is_called THEN setval(res.staging_seq, seq.last_value + res.inc)
                    ELSE setval(res.staging_seq, seq.last_value) 
                END
            FROM res
            JOIN (
                SELECT
                    ''%s'' AS seq_name,
                    is_called,
                    last_value
                FROM %I
            ) seq
            ON (res.target_seq = seq.seq_name)', seq_name, seq_name::regclass)
            INTO next_val;
            RAISE NOTICE 'Next value: %', next_val;
        END LOOP;

        RAISE NOTICE 'Enabling triggers from target table onto staging table';
        
        FOR staging_def IN
            SELECT 
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        pg_get_triggerdef(oid), 
                        'BEFORE\s+INSERT\s+ON\s+public.' || _table, 
                        'BEFORE INSERT ON public.' || staging_table
                    ),
                    'CREATE\s+TRIGGER\s+',
                    'CREATE TRIGGER staging_'
                )
            FROM   pg_trigger t
            WHERE  tgrelid::text = format('%s::regclass', _table)
        LOOP
            EXECUTE format('%s', staging_def);
        END LOOP;
    END;
$$ LANGUAGE plpgsql;

SELECT create_staging_table(:'staging_table', :'table');