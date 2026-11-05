# Bodegas del Atuel — TPI Bases de Datos
Modelado y desarrollo de la base de datos de **Bodegas del Atuel**, una empresa
vitivinícola ficticia que integra la producción de uva y vino con su distribución
y venta a través de una red de salas de venta.

> Estado: Etapa 1 — Modelado

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
| Jamardo, Camila | 10842 | [@camjamardo](https://github.com/camjamardo) |
| Sirotiuk, Juliana | — | [@julisirotiuk](https://github.com/julisirotiuk) |
 
---

## Requisitos
Para trabajar con el proyecto en local:

- [PostgreSQL 14+](https://www.postgresql.org/download/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (se utiliza desde la Etapa 2)
- Cliente SQL: `psql`, DBeaver o pgAdmin
- [draw.io](https://app.diagrams.net/) para editar el DER
- Python 3.11+ (Etapa 3, carga masiva)
- Git

---

## Nota académica

Proyecto desarrollado para la cátedra **Bases de Datos** de la carrera
**Ingeniería en Sistemas de Información** de la **UTN Facultad Regional San Rafael**,
ciclo lectivo 2026.

«Bodegas del Atuel» es una empresa ficticia. Los datos utilizados son generados
con fines exclusivamente académicos.

