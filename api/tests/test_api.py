"""Pruebas de integracion de la API contra PostgreSQL real.

Se ejecutan contra la base de docker compose, con triggers, funciones y
procedimientos activos. Cada prueba limpia las filas que crea.
"""

from __future__ import annotations

from decimal import Decimal

from fastapi.testclient import TestClient

from tests.conftest import Creados
from tests.helpers import (
    contar_comprobantes_cliente,
    crear_cliente,
    crear_stock,
    crear_vino,
    existe_vino,
    stock_sala,
    sufijo,
    total_comprobante_bd,
)


def test_salud_usa_rol_api(client: TestClient) -> None:
    respuesta = client.get("/salud")
    assert respuesta.status_code == 200, respuesta.text
    datos = respuesta.json()
    assert datos["status"] == "ok"
    assert datos["base_de_datos"] == "ok"
    assert datos["current_user"] == "rol_api"


def test_catalogo_y_reportes(client: TestClient, catalogo: dict) -> None:
    respuesta = client.get("/vinos", params={"page_size": 3})
    assert respuesta.status_code == 200, respuesta.text
    datos = respuesta.json()
    assert datos["total"] >= 1
    assert len(datos["items"]) <= 3
    assert datos["page"] == 1
    assert datos["page_size"] == 3

    tintos = client.get("/vinos", params={"tipo": "tinto", "page_size": 5})
    assert tintos.status_code == 200, tintos.text
    assert all(vino["tipo"] == "tinto" for vino in tintos.json()["items"])

    top = client.get("/reportes/top-vinos")
    assert top.status_code == 200, top.text
    assert isinstance(top.json(), list)

    ventas = client.get("/reportes/ventas-por-sala")
    assert ventas.status_code == 200, ventas.text
    assert isinstance(ventas.json(), list)

    sin_stock = client.get("/reportes/vinos-sin-stock", params={"sala": catalogo["id_sala"]})
    assert sin_stock.status_code == 200, sin_stock.text
    assert isinstance(sin_stock.json(), list)

    transportista = client.get("/reportes/transportista-activo")
    assert transportista.status_code == 200, transportista.text


def test_crud_clientes_cuatro_tipos(client: TestClient, catalogo: dict, creados: Creados) -> None:
    creados_por_tipo = {}
    for tipo in ("cliente_comun", "socio_club", "distribuidor", "exportador"):
        datos = crear_cliente(client, creados, catalogo, tipo=tipo)
        assert datos["tipo"] == tipo
        assert datos["estado_activo"] is True
        creados_por_tipo[tipo] = datos

    exportador = creados_por_tipo["exportador"]
    assert len(exportador["permisos"]) == 1
    assert exportador["pais_destino"] == "Brasil"
    assert exportador["descuento_especial"] == "0.35"

    listado = client.get(
        "/clientes",
        params={"documento": exportador["numero_documento"], "page_size": 5},
    )
    assert listado.status_code == 200, listado.text
    assert any(
        cliente["id"] == exportador["id"] for cliente in listado.json()["items"]
    )
    assert client.get(f"/clientes/{exportador['id']}").status_code == 200

    distribuidor = creados_por_tipo["distribuidor"]
    assert distribuidor["zona_cobertura"] == "Zona Sur"
    assert distribuidor["numero_habilitacion"] == "HAB-001"

    id_cliente = creados_por_tipo["cliente_comun"]["id"]
    actualizado = client.put(
        f"/clientes/{id_cliente}",
        json={"nombre": "Nombre Actualizado", "apellido": "Apellido Actualizado"},
    )
    assert actualizado.status_code == 200, actualizado.text
    assert actualizado.json()["nombre"] == "Nombre Actualizado"

    eliminado = client.delete(f"/clientes/{id_cliente}")
    assert eliminado.status_code == 204, eliminado.text
    assert client.get(f"/clientes/{id_cliente}").status_code == 404


def test_cambio_de_tipo_conserva_historial_y_crea_version_activa(
    client: TestClient, catalogo: dict, creados: Creados
) -> None:
    original = crear_cliente(client, creados, catalogo, tipo="cliente_comun")

    respuesta = client.put(
        f"/clientes/{original['id']}",
        json={
            "tipo": "distribuidor",
            "razon_social": "Distribuidora Versionada",
            "zona_cobertura": "Zona Centro",
            "numero_habilitacion": "HAB-002",
            "nombre": "Nombre",
            "apellido": "Apellido",
        },
    )
    assert respuesta.status_code == 200, respuesta.text
    nuevo = respuesta.json()
    assert nuevo["id"] != original["id"]
    assert nuevo["tipo"] == "distribuidor"
    assert nuevo["estado_activo"] is True
    assert nuevo["zona_cobertura"] == "Zona Centro"
    creados.clientes.append(nuevo["id"])

    anterior = client.get(f"/clientes/{original['id']}")
    assert anterior.status_code == 200, anterior.text
    assert anterior.json()["estado_activo"] is False

    # Se elimina la versión anterior para no dejar residuos de la prueba.
    assert client.delete(f"/clientes/{original['id']}").status_code == 204


def test_crear_actualizar_y_eliminar_vino(
    client: TestClient, catalogo: dict, creados: Creados
) -> None:
    creado = crear_vino(client, creados, catalogo)
    codigo = creado["codigo"]
    assert creado["stock_total"] == 0
    assert len(creado["cepas"]) == 2
    assert all(cepa["porcentaje"] in {"60.00", "40.00"} for cepa in creado["cepas"])

    detalle = client.get(f"/vinos/{codigo}")
    assert detalle.status_code == 200, detalle.text
    assert detalle.json()["bodega"]["cuit"] == catalogo["cuit_bodega"]
    assert detalle.json()["stock_total"] == 0

    traza = client.get(f"/reportes/trazabilidad/{codigo}")
    assert traza.status_code == 200, traza.text
    assert traza.json()["cepas"] is not None

    actualizado = client.put(f"/vinos/{codigo}", json={"precio": "1200.00"})
    assert actualizado.status_code == 200, actualizado.text
    assert actualizado.json()["precio"] == "1200.00"

    eliminado = client.delete(f"/vinos/{codigo}")
    assert eliminado.status_code == 204, eliminado.text
    assert client.get(f"/vinos/{codigo}").status_code == 404


def test_precio_negativo_es_rechazado_por_check(
    client: TestClient, catalogo: dict
) -> None:
    nombre = f"API TEST NEGATIVO {sufijo()}"
    respuesta = client.post(
        "/vinos",
        json={
            "nombre": nombre,
            "tipo": "tinto",
            "anada": 2024,
            "volumen_ml": 750,
            "graduacion": "13.50",
            "precio": "-1.00",
            "cuit_bodega": catalogo["cuit_bodega"],
            "cepas": [
                {"id_cepa": catalogo["cepa_ids"][0], "porcentaje": "100.00"}
            ],
            "maridajes": [],
        },
    )
    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json()["error"]["codigo"] == "23514"
    assert not existe_vino(nombre)


def test_composicion_distinta_de_100_revierte_la_transaccion(
    client: TestClient, catalogo: dict
) -> None:
    nombre = f"API TEST COMPOSICION {sufijo()}"
    respuesta = client.post(
        "/vinos",
        json={
            "nombre": nombre,
            "tipo": "tinto",
            "anada": 2024,
            "volumen_ml": 750,
            "graduacion": "13.50",
            "precio": "1000.00",
            "cuit_bodega": catalogo["cuit_bodega"],
            "cepas": [
                {"id_cepa": catalogo["cepa_ids"][0], "porcentaje": "60.00"},
                {"id_cepa": catalogo["cepa_ids"][1], "porcentaje": "30.00"},
            ],
            "maridajes": [],
        },
    )
    assert respuesta.status_code == 409, respuesta.text
    assert respuesta.json()["error"]["codigo"] == "P0001"
    assert not existe_vino(nombre)


def test_venta_sin_stock_es_rechazada_y_no_deja_cabecera(
    client: TestClient, catalogo: dict, creados: Creados
) -> None:
    vino = crear_vino(client, creados, catalogo)
    cliente = crear_cliente(client, creados, catalogo, tipo="cliente_comun")

    respuesta = client.post(
        "/comprobantes",
        json={
            "id_cliente": cliente["id"],
            "id_sala_venta": catalogo["id_sala"],
            "renglones": [{"codigo_vino": vino["codigo"], "cantidad": 1}],
        },
    )
    assert respuesta.status_code == 409, respuesta.text
    assert "Stock insuficiente" in respuesta.json()["error"]["mensaje"]
    assert contar_comprobantes_cliente(cliente["id"]) == 0


def test_venta_exitosa_con_totales_y_descuento_de_la_base(
    client: TestClient, catalogo: dict, creados: Creados
) -> None:
    vino = crear_vino(client, creados, catalogo, precio="1000.00")
    crear_stock(
        client,
        creados,
        catalogo,
        codigo_vino=vino["codigo"],
        cantidad=10,
    )
    cliente = crear_cliente(client, creados, catalogo, tipo="socio_club")

    respuesta = client.post(
        "/comprobantes",
        json={
            "id_cliente": cliente["id"],
            "id_sala_venta": catalogo["id_sala"],
            "renglones": [{"codigo_vino": vino["codigo"], "cantidad": 2}],
        },
    )
    assert respuesta.status_code == 201, respuesta.text
    datos = respuesta.json()
    creados.comprobantes.append(datos["numero"])

    assert datos["subtotal"] == "2000.00"
    assert datos["descuento_aplicado"] == "0.10"
    assert datos["descuento_total"] == "200.00"
    assert datos["total"] == "1800.00"
    assert datos["renglones"][0]["precio_unitario"] == "1000.00"
    assert datos["renglones"][0]["subtotal_renglon"] == "2000.00"
    assert Decimal(datos["total"]) == total_comprobante_bd(datos["numero"])
    assert stock_sala(catalogo["id_sala"], vino["codigo"]) == 8

    consultado = client.get(f"/comprobantes/{datos['numero']}")
    assert consultado.status_code == 200, consultado.text
    assert consultado.json()["total"] == "1800.00"
    assert consultado.json()["cliente"]["id"] == cliente["id"]


def test_no_se_puede_procesar_una_transferencia_no_terminada(
    client: TestClient, catalogo: dict, creados: Creados
) -> None:
    vino = crear_vino(client, creados, catalogo)
    transferencia = client.post(
        "/transferencias", json={"id_sala_venta": catalogo["id_sala"]}
    )
    assert transferencia.status_code == 201, transferencia.text
    numero = transferencia.json()["numero"]
    creados.transferencias.append(numero)

    renglon = client.post(
        f"/transferencias/{numero}/renglones",
        json={"codigo_vino": vino["codigo"], "cantidad": 1},
    )
    assert renglon.status_code == 200, renglon.text

    procesar = client.post(f"/transferencias/{numero}/procesar")
    assert procesar.status_code == 409, procesar.text

    actual = client.get(f"/transferencias/{numero}")
    assert actual.status_code == 200, actual.text
    assert actual.json()["estado"] == "en_confeccion"


def test_no_se_puede_transferir_sin_stock_en_deposito(
    client: TestClient, catalogo: dict, creados: Creados
) -> None:
    vino = crear_vino(client, creados, catalogo)
    transferencia = client.post(
        "/transferencias", json={"id_sala_venta": catalogo["id_sala"]}
    )
    assert transferencia.status_code == 201, transferencia.text
    numero = transferencia.json()["numero"]
    creados.transferencias.append(numero)

    renglon = client.post(
        f"/transferencias/{numero}/renglones",
        json={"codigo_vino": vino["codigo"], "cantidad": 1},
    )
    assert renglon.status_code == 200, renglon.text
    assert client.post(f"/transferencias/{numero}/terminar").status_code == 200

    procesar = client.post(f"/transferencias/{numero}/procesar")
    assert procesar.status_code == 409, procesar.text
    assert stock_sala(catalogo["id_sala"], vino["codigo"]) == 0


def test_inyeccion_sql_en_filtro_se_trata_como_texto(
    client: TestClient, catalogo: dict
) -> None:
    antes = client.get("/vinos", params={"page_size": 1}).json()["total"]

    inyeccion = client.get("/vinos", params={"nombre": "' OR 1=1 --"})
    assert inyeccion.status_code == 200, inyeccion.text
    assert inyeccion.json()["items"] == []

    tipo_invalido = client.get("/vinos", params={"tipo": "tinto' OR '1'='1"})
    assert tipo_invalido.status_code == 422, tipo_invalido.text
    assert tipo_invalido.json()["error"]["codigo"] == "VALIDACION"

    despues = client.get("/vinos", params={"page_size": 1}).json()["total"]
    assert despues == antes


def test_referencia_inexistente_devuelve_422(
    client: TestClient, catalogo: dict
) -> None:
    nombre = f"API TEST FK {sufijo()}"
    respuesta = client.post(
        "/vinos",
        json={
            "nombre": nombre,
            "tipo": "tinto",
            "anada": 2024,
            "volumen_ml": 750,
            "graduacion": "13.50",
            "precio": "1000.00",
            "cuit_bodega": "00000000000",
            "cepas": [
                {"id_cepa": catalogo["cepa_ids"][0], "porcentaje": "100.00"}
            ],
            "maridajes": [],
        },
    )
    assert respuesta.status_code == 422, respuesta.text
    assert respuesta.json()["error"]["codigo"] == "23503"
    assert not existe_vino(nombre)
