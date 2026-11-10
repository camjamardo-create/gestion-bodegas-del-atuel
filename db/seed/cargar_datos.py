#!/usr/bin/env python3
"""Carga masiva determinista para Bodegas del Atuel (Etapa 3).

Ejemplos:
  python db/seed/cargar_datos.py --limpiar
  python db/seed/cargar_datos.py --limpiar --escala 0.1 --modo lotes
  python db/seed/cargar_datos.py --benchmark --benchmark-filas 10000
  python db/seed/cargar_datos.py --compare-hashes h1.json h2.json
"""
from __future__ import annotations

import argparse
import sys
from datetime import date
from pathlib import Path

from cargador import (
    analizar_y_setval,
    calcular_hashes,
    cargar_todo,
    comparar_hashes,
    conectar,
    descripcion_conexion,
    ejecutar_benchmark,
    ejecutar_controles,
    truncar_todo,
    verificar_vacias,
)
from generador import DataGenerator

BASE_DIR = Path(__file__).resolve().parent
CONTROLES = BASE_DIR / "consultas_control.sql"


def _parsear_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Carga masiva determinista de Bodegas del Atuel (Etapa 3)."
    )
    p.add_argument("--seed", type=int, default=42, help="Semilla para random y Faker (default 42)")
    p.add_argument("--fecha-ref", default="2026-11-10",
                   help="Fecha de referencia YYYY-MM-DD (default 2026-11-10)")
    p.add_argument("--escala", type=float, default=1.0,
                   help="Escala de volúmenes; 0.1 para una carga reducida (default 1.0)")
    p.add_argument("--modo", choices=["copy", "lotes", "fila-por-fila"], default="copy",
                   help="Método de inserción (default copy)")
    p.add_argument("--limpiar", action="store_true",
                   help="Trunca TODAS las tablas (incluidos catálogos) y recarga")
    p.add_argument("--sin-control", action="store_true",
                   help="No ejecuta db/seed/consultas_control.sql al final")
    p.add_argument("--hash-out", type=Path,
                   help="Escribe un JSON con conteos y hashes SHA-256 por tabla")
    p.add_argument("--benchmark", action="store_true",
                   help="Ejecuta solo el benchmark de carga de cliente y sale")
    p.add_argument("--benchmark-filas", type=int, default=10_000,
                   help="Filas para el benchmark (default 10000)")
    p.add_argument("--compare-hashes", nargs=2, metavar=("A", "B"),
                   help="Compara dos JSON de --hash-out y sale")
    return p.parse_args()


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = _parsear_args()

    if args.compare_hashes:
        ok = comparar_hashes(Path(args.compare_hashes[0]), Path(args.compare_hashes[1]))
        return 0 if ok else 1

    if args.escala <= 0:
        print("ERROR: --escala debe ser mayor que 0", file=sys.stderr)
        return 2
    try:
        fecha_ref = date.fromisoformat(args.fecha_ref)
    except ValueError:
        print("ERROR: --fecha-ref debe tener formato YYYY-MM-DD", file=sys.stderr)
        return 2

    if args.benchmark:
        conn = conectar()
        try:
            print(f"Conectado a {descripcion_conexion(conn)}")
            if args.benchmark_filas <= 0:
                print("ERROR: --benchmark-filas debe ser mayor que 0", file=sys.stderr)
                return 2
            ejecutar_benchmark(conn, args.seed, args.benchmark_filas, fecha_ref)
        finally:
            conn.close()
        return 0

    print("Generando datos en memoria...")
    generador = DataGenerator(seed=args.seed, fecha_ref=fecha_ref, escala=args.escala)
    generador.generate_all()
    print("Conteos generados:")
    for tabla in generador.rows:
        print(f"  {tabla:<32} {len(generador.rows[tabla]):>8}")

    conn = conectar()
    try:
        print(f"Conectado a {descripcion_conexion(conn)}")
        if args.limpiar:
            truncar_todo(conn)
        else:
            verificar_vacias(conn)

        cargar_todo(conn, generador.rows, args.modo)
        analizar_y_setval(conn)

        if not args.sin_control:
            ejecutar_controles(conn, CONTROLES, fecha_ref)

        if args.hash_out:
            calcular_hashes(
                conn,
                {
                    "seed": args.seed,
                    "fecha_ref": fecha_ref.isoformat(),
                    "escala": args.escala,
                    "modo": args.modo,
                },
                args.hash_out,
            )
    finally:
        conn.close()

    print("\nCarga finalizada correctamente.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
