-- 01_migraciones.sql
-- Se ejecuta una sola vez, cuando el volumen de PostgreSQL esta vacio.
-- Aplica las migraciones en el mismo orden que documenta el README.

\set ON_ERROR_STOP on

\echo 'Aplicando 001_esquema.sql'
\i /migrations/001_esquema.sql
\echo 'Aplicando 002_constraints.sql'
\i /migrations/002_constraints.sql
\echo 'Aplicando 003_funciones.sql'
\i /migrations/003_funciones.sql
\echo 'Aplicando 004_procedimientos.sql'
\i /migrations/004_procedimientos.sql
\echo 'Aplicando 005_triggers.sql'
\i /migrations/005_triggers.sql
\echo 'Aplicando 006_vistas.sql'
\i /migrations/006_vistas.sql
\echo 'Aplicando 007_roles.sql'
\i /migrations/007_roles.sql
\echo 'Aplicando 008_indices.sql'
\i /migrations/008_indices.sql
