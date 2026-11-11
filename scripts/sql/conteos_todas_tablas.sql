-- Conteos de todas las tablas base de public, con una fila por tabla.
-- Se usa para comparar la base original con una restauración.
\pset tuples_only on
\pset format unaligned
\pset fieldsep '|'
\pset footer off

SELECT format(
    'SELECT %L AS tabla, count(*) AS filas FROM %I.%I',
    table_name,
    table_schema,
    table_name
)
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name
\gexec
