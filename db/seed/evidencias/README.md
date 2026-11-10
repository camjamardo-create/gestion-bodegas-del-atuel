# Evidencias de la corrida Etapa 3

Estos archivos son la salida de `--hash-out` para la corrida real del
2026-11-10 con `--seed 42`, `--fecha-ref 2026-11-10`, `--escala 1.0` y
`--modo copy`.

- `hashes_run1.json`: primera carga completa.
- `hashes_run2.json`: segunda carga completa, misma semilla y fecha.
- `hashes_run3.json`: tercera carga completa usada para medir el tiempo total.
- `hashes_restore.json`: base restaurada desde `dump_completo.sql.gz`.

Los cuatro archivos tienen el mismo campo `combined`:

```
5865ce1cc63f998d109af49a3f9e44656ff8935f3a743459ccf1697cb1d01745
```

Eso verifica que la carga es reproducible y que el dump/restore conserva los
datos. Los archivos incluyen el conteo y el SHA-256 de cada tabla, calculados
con `COPY (SELECT * FROM tabla ORDER BY clave) TO STDOUT`.

El dump comprimido no se versiona (está en `.gitignore`); se regenera con
`db/seed/generar_dump.sh`.
