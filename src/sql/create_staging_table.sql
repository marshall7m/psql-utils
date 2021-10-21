CREATE OR REPLACE FUNCTION create_staging_table(staging_table VARCHAR, _table VARCHAR)
    RETURNS VOID AS $$
    DECLARE
        id_rec RECORD;
        trig_record RECORD;
        seq_rec RECORD;
    BEGIN
        RAISE NOTICE 'Creating staging table: %s', staging_table;
        EXECUTE format('
        DROP TABLE IF EXISTS %1$s;
        --exclude indexes so staging table contains no identity column that will conflict with altering the default
        CREATE TABLE %1$s (LIKE %2$s INCLUDING DEFAULTS INCLUDING CONSTRAINTS)', staging_table, _table);

        RAISE NOTICE 'Mounting identity column sequences to staging table';

        EXECUTE format('
        CREATE TEMP TABLE res AS 
            SELECT 
                attname,
                pg_get_serial_sequence(''%1$s'', attname) AS seq
            FROM pg_attribute
            WHERE attrelid = ''%1$I''::regclass
            AND pg_get_serial_sequence(''%1$s'', attname) IS NOT NULL
            AND attidentity != ''''
        ', _table);

        FOR seq_rec IN (SELECT * FROM res)
        LOOP
            RAISE NOTICE 'Sequence: %', seq_rec.seq;
            RAISE NOTICE 'Column: %', seq_rec.attname;
            EXECUTE format('ALTER TABLE %I ALTER COLUMN %I SET DEFAULT nextval(''%s'');', staging_table, seq_rec.attname, seq_rec.seq);
        END LOOP;

        RAISE NOTICE 'Enabling triggers from target table onto staging table';
        
        FOR trig_record IN
            SELECT
                tgname,
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        pg_get_triggerdef(oid), 
                        'BEFORE\s+INSERT\s+ON\s+public.' || _table, 
                        'BEFORE INSERT ON public.' || staging_table
                    ),
                    'CREATE\s+TRIGGER\s+',
                    'CREATE TRIGGER staging_'
                ) AS def
            FROM   pg_trigger t
            WHERE  tgrelid = _table::regclass
        LOOP
            RAISE NOTICE 'Trigger name: %', trig_record.tgname;
            EXECUTE format('%s', trig_record.def);
        END LOOP;
    END;
$$ LANGUAGE plpgsql;

SELECT create_staging_table(:'staging_table', :'table');