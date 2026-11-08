# Bodegas del Atuel — TPI Bases de Datos
Modelado y desarrollo de la base de datos de **Bodegas del Atuel**, una empresa
vitivinícola ficticia que integra la producción de uva y vino con su distribución
y venta a través de una red de salas de venta.


## Descripción del proyecto

El objetivo es construir el corazón de un sistema de gestión para una bodega:
un modelo de datos normalizado, implementado en PostgreSQL, que garantice las
reglas de negocio dentro de la propia base y que luego sea consumido por una API
REST y un front.

El sistema cubre, entre otros procesos:

- **Red comercial:** localidades, salas de venta, empleados y encargados regionales.
- **Producción:** fincas, parcelas, cepas, campañas, lotes de uva y análisis de calidad.
- **Producto:** bodegas, vinos, composición de cepas, maridajes y precios.
- **Ventas:** clientes (socios, distribuidores, exportadores), comprobantes y renglones.
- **Logística y stock:** depósito central, ingresos, transferencias y stock por sala.
- **Auditoría:** historial de cambios de precio de los vinos.

La base se implementa con **SQL escrito a mano**. No se permite ORM ni
herramientas que oculten el SQL.

---

## Integrantes

|   Integrante   |   Legajo   |   GitHub   |
|   ----------   |   ------   |   ------   |
| Jamardo, Camila | 10842 | [@camjamardo-create](https://github.com/camjamardo-create) |
| Sirotiuk, Juliana | — | [@julisirotiuk](https://github.com/julisirotiuk) |
 
---

## Requisitos
Para trabajar con el proyecto en local:

- [PostgreSQL 14+](https://www.postgresql.org/download/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- Cliente SQL: `psql`, DBeaver o pgAdmin
- [draw.io](https://app.diagrams.net/) para editar el DER
- Python 3.11+ (Etapa 3, carga masiva)
- Git

---

## Base de datos local

Ejecutar desde la raíz del repositorio. 

Borrar la base si existe, crearla y aplicar esquemas 001 - 007:

```bash 
dropdb -U postgres --if-exists bodegas_del_atuel
createdb -U postgres -E UTF8 -T template0 bodegas_del_atuel
psql -U postgres -d bodegas_del_atuel -v ON_ERROR_STOP=1 -f db/migrations/001_esquema.sql
```

> **Atención:** `dropdb` elimina todos los datos de la base. Usarlo solo en desarrollo o hacer un backup antes. 


### Cómo saber que salió bien

El script corre dentro de una transacción: termina con `COMMIT`, y si aparece algún `ERROR` se detiene y no se crea nada.

Conectarse a la base:

```bash
psql -U postgres -d bodegas_del_atuel
```

y verificar:

| Comando | Qué debe mostrar |
|---|---|
| `\dt` | Las 30 tablas del esquema |
| `\d bodega` | Columnas, tipos y constraints de la tabla (se puede repetir con cualquier otra, por ejemplo `\d finca`) |
| `\dD` | Los dominios: `cuit_dominio` y `cp_dominio` |
| `\dT` | Los tipos: `tipo_vino`, `tipo_cliente`, `tipo_cepa`, `tipo_empleado`, `tipo_estado` y `dia_semana` (también aparecen los dominios) |

Salir de `psql` con `\q`.

---

## Nota académica

Proyecto desarrollado para la cátedra **Bases de Datos** de la carrera
**Ingeniería en Sistemas de Información** de la **UTN Facultad Regional San Rafael**,
ciclo lectivo 2026.

«Bodegas del Atuel» es una empresa ficticia. Los datos utilizados son generados
con fines exclusivamente académicos.

