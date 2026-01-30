
-- ============================================================================
-- Function: finalize_materialized_view
-- Description:
--   Finalizes the creation of a materialized view using a safe and consistent
--   workflow. This includes:
--     1. Dropping the temporary view if it exists.
--     2. Creating the temporary view using provided SQL.
--     3. Verifying the view was created successfully.
--     4. Creating temporary indexes: GiST on geometry and UNIQUE on specified columns.
--     5. Dropping the final view (if it exists).
--     6. Renaming the temporary view and indexes to their final names.
--     7. Logging each step clearly for debugging and auditing.
--
-- Parameters:
--   tmp_mview_name TEXT    - Temporary name used during creation (e.g. 'view_tmp').
--   mview_name     TEXT    - Final target name for the materialized view.
--   unique_columns TEXT    - Comma-separated list of columns for UNIQUE index (e.g. 'osm_id, type').
--   sql_create     TEXT    - SQL statement to create the temporary materialized view.
--
-- Notes:
--   - Designed to be reused by multiple materialized view creation functions.
--   - All index names follow a consistent pattern: idx_<view>_geom, idx_<view>_uid.
--   - If the temporary view creation fails, the function raises an exception.
--   - Only proceeds to rename if the temp view is confirmed to exist.
-- ============================================================================
DROP FUNCTION IF EXISTS finalize_materialized_view;

CREATE OR REPLACE FUNCTION finalize_materialized_view(
    tmp_mview_name TEXT,
    mview_name TEXT,
    unique_columns TEXT,
    sql_create TEXT
) RETURNS VOID AS $$
DECLARE
    tmp_exists BOOLEAN;
    geom_index_tmp TEXT := format('idx_%s_geom', tmp_mview_name);
    uid_index_tmp  TEXT := format('idx_%s_uid', tmp_mview_name);
    geom_index_final TEXT := format('idx_%s_geom', mview_name);
    uid_index_final  TEXT := format('idx_%s_uid', mview_name);
BEGIN
    -- Temporary memory configuration for the view creation
    SET LOCAL work_mem = '512MB';
    SET LOCAL maintenance_work_mem = '1GB';

    -- Step 1: Log and drop temp view
    RAISE NOTICE '==> [START] Creating view: %', mview_name;
    RAISE NOTICE '==> [DROP TEMP] Dropping tmp view: %', tmp_mview_name;
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', tmp_mview_name);

    -- Step 2: Create temp view
    RAISE NOTICE '==> [CREATE TEMP] Creating tmp view: %', tmp_mview_name;
    EXECUTE sql_create;

    -- Step 3: Validate creation
    SELECT EXISTS (
        SELECT 1 FROM pg_matviews WHERE matviewname = tmp_mview_name
    ) INTO tmp_exists;

    IF NOT tmp_exists THEN
        RAISE EXCEPTION '❌ Temp view % not created correctly', tmp_mview_name;
    END IF;

    -- Step 4: Create indexes on temp
    RAISE NOTICE '==> [INDEX] Creating GiST index on geometry (tmp)';
    EXECUTE format('DROP INDEX IF EXISTS %I;', geom_index_tmp);
    EXECUTE format('CREATE INDEX %I ON %I USING GIST (geometry);', geom_index_tmp, tmp_mview_name);

    RAISE NOTICE '==> [INDEX] Creating UNIQUE index on (%s) (tmp)', unique_columns;
    EXECUTE format('DROP INDEX IF EXISTS %I;', uid_index_tmp);
    EXECUTE format('CREATE UNIQUE INDEX %I ON %I (%s);', uid_index_tmp, tmp_mview_name, unique_columns);

    -- Step 5: Drop final if exists
    RAISE NOTICE '==> [DROP OLD] Dropping old view and indices: %', mview_name;
    EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I CASCADE;', mview_name);

    -- Step 6: Rename view and indexes
    RAISE NOTICE '==> [RENAME VIEW] % → %', tmp_mview_name, mview_name;
    EXECUTE format('ALTER MATERIALIZED VIEW %I RENAME TO %I;', tmp_mview_name, mview_name);

    RAISE NOTICE '==> [RENAME INDEX] % → %', geom_index_tmp, geom_index_final;
    EXECUTE format('ALTER INDEX %I RENAME TO %I;', geom_index_tmp, geom_index_final);

    RAISE NOTICE '==> [RENAME INDEX] % → %', uid_index_tmp, uid_index_final;
    EXECUTE format('ALTER INDEX %I RENAME TO %I;', uid_index_tmp, uid_index_final);

    RAISE NOTICE '==> [DONE] ✅ View % created successfully with indexes.', mview_name;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- Function: create_generic_mview
-- Description:
--   Creates a materialized view from the specified input table using a temporary
--   intermediate view, and finalizes it through the finalize_materialized_view
--   procedure. It includes:
--     - All columns from the source table except geometry, name, start_date, end_date.
--     - `osm_id` transformed as ABS(osm_id) AS osm_id.
--     - `name`, `start_date`, `end_date` cleaned with NULLIF(..., '').
--     - `start_decdate`, `end_decdate` derived using pad_date() and isodatetodecimaldate().
--     - Language-specific name columns appended via get_language_columns().
--     - `geometry` column preserved at the end.
--
-- Parameters:
--   input_table     TEXT      - Name of the source table.
--   mview_name       TEXT      - Final name of the materialized view to create.
--   unique_columns  TEXT[]    - Columns used for DISTINCT ON and unique index.
--
-- Notes:
--   - Deduplication uses DISTINCT ON and ORDER BY with provided unique_columns.
--   - GiST index is created on geometry.
--   - Unique index is created on the unique_columns set.
--   - View creation is safe and atomic via temporary view, validated, indexed,
--     and renamed to final name using finalize_materialized_view().
-- ============================================================================

DROP FUNCTION IF EXISTS create_generic_mview(TEXT, TEXT, TEXT[]);

CREATE OR REPLACE FUNCTION create_generic_mview(
  input_table TEXT,
  mview_name TEXT,
  unique_columns TEXT[] DEFAULT ARRAY['osm_id']
)
RETURNS void AS $$
DECLARE
    lang_columns TEXT;
    table_columns TEXT;
    quoted_unique_cols TEXT;
    sql_create TEXT;
    tmp_mview_name TEXT := mview_name || '_tmp';
BEGIN
    lang_columns := get_language_columns();

    -- Build list of columns, replacing 'osm_id' with ABS(osm_id) AS osm_id
    SELECT string_agg(
        CASE
            WHEN column_name = 'osm_id' THEN 'ABS(osm_id) AS osm_id'
            ELSE quote_ident(column_name)
        END,
        ', '
    )
    INTO table_columns
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = input_table
      AND column_name NOT IN ('geometry', 'name', 'start_date', 'end_date');

    -- Quoted unique columns for DISTINCT ON and ORDER BY
    SELECT string_agg(quote_ident(c), ', ')
    INTO quoted_unique_cols
    FROM unnest(unique_columns) AS c;

    -- Generate SQL for creating the materialized view
    sql_create := format($sql$
        CREATE MATERIALIZED VIEW %I AS
        SELECT DISTINCT ON (%s)
            %s,
            NULLIF(name, '') AS name,
            NULLIF(start_date, '') AS start_date,
            NULLIF(end_date, '') AS end_date,
            public.isodatetodecimaldate(public.pad_date(start_date, 'start'), FALSE) AS start_decdate,
            public.isodatetodecimaldate(public.pad_date(end_date, 'end'), FALSE) AS end_decdate,
            %s,
            geometry
        FROM %I
        WHERE geometry IS NOT NULL
        ORDER BY %s;
    $sql$,
        tmp_mview_name,
        quoted_unique_cols,
        table_columns,
        lang_columns,
        input_table,
        quoted_unique_cols
    );

    -- Use shared finalization routine
    PERFORM finalize_materialized_view(
        tmp_mview_name,
        mview_name,
        array_to_string(unique_columns, ', '),
        sql_create
    );
END;
$$ LANGUAGE plpgsql;
