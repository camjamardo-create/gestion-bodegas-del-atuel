(() => {
  "use strict";

  const config = window.__APP_CONFIG__ || { apiBaseUrl: "/api" };
  const apiBaseUrl = String(config.apiBaseUrl || "/api").replace(/\/+$/, "");
  const view = document.getElementById("view");
  const statusChip = document.getElementById("api-status");
  const toastBox = document.getElementById("toast");

  const state = {
    route: "inicio",
    params: new URLSearchParams(),
    vinos: {
      nombre: "",
      tipo: "",
      anada: "",
      page: 1,
      pageSize: 20,
      selected: null,
    },
    clientes: {
      tipo: "",
      estado: "",
      documento: "",
      page: 1,
      pageSize: 20,
      selected: null,
    },
    ventas: {
      result: null,
      prefill: null,
      clientes: [],
    },
    stock: {
      ingreso: null,
      transferencia: null,
    },
  };

  let renderToken = 0;
  let toastTimer = null;

  class ApiError extends Error {
    constructor(status, body) {
      const detalle = body && body.error ? body.error : null;
      super(detalle && detalle.mensaje ? detalle.mensaje : `Error HTTP ${status}`);
      this.name = "ApiError";
      this.status = status;
      this.codigo = detalle && detalle.codigo ? detalle.codigo : "HTTP";
      this.regla = detalle && detalle.regla ? detalle.regla : null;
    }
  }

  function esc(value) {
    return String(value === null || value === undefined ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function esVacio(value) {
    return value === null || value === undefined || String(value).trim() === "";
  }

  function apiUrl(path) {
    const limpio = path.startsWith("/") ? path : `/${path}`;
    return `${apiBaseUrl}${limpio}`;
  }

  async function api(path, options = {}) {
    const headers = { Accept: "application/json", ...(options.headers || {}) };
    let body = options.body;
    if (body !== undefined && body !== null && typeof body !== "string") {
      headers["Content-Type"] = "application/json";
      body = JSON.stringify(body);
    }

    let response;
    try {
      response = await fetch(apiUrl(path), {
        ...options,
        headers,
        body,
        cache: options.cache || "no-store",
      });
    } catch (error) {
      throw new ApiError(0, {
        error: {
          codigo: "RED",
          mensaje: "No se pudo conectar con la API. Verifique API_BASE_URL y que el servicio esté disponible.",
        },
      });
    }

    const text = await response.text();
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch (error) {
        data = { error: { codigo: "RESPUESTA", mensaje: "La API devolvió una respuesta que no es JSON." } };
      }
    }

    if (!response.ok) {
      throw new ApiError(response.status, data);
    }
    return data;
  }

  function money(value) {
    if (esVacio(value)) return "—";
    const numero = Number(value);
    if (!Number.isFinite(numero)) return esc(value);
    return numero.toLocaleString("es-AR", {
      style: "currency",
      currency: "ARS",
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
  }

  function dateText(value) {
    if (!value) return "—";
    const fecha = new Date(`${String(value).slice(0, 10)}T00:00:00`);
    if (Number.isNaN(fecha.getTime())) return esc(value);
    return fecha.toLocaleDateString("es-AR", { day: "2-digit", month: "2-digit", year: "numeric" });
  }

  function numberText(value) {
    if (esVacio(value)) return "—";
    const numero = Number(value);
    if (!Number.isFinite(numero)) return esc(value);
    return numero.toLocaleString("es-AR");
  }

  function tipoVino(value) {
    const etiquetas = {
      tinto: "Tinto",
      blanco: "Blanco",
      rosado: "Rosado",
      espumante: "Espumante",
    };
    return etiquetas[value] || String(value || "—");
  }

  function tipoCliente(value) {
    const etiquetas = {
      cliente_comun: "Cliente común",
      socio_club: "Socio del club",
      distribuidor: "Distribuidor",
      exportador: "Exportador",
    };
    return etiquetas[value] || String(value || "—");
  }

  function estadoBadge(value) {
    const etiquetas = {
      en_confeccion: "En confección",
      terminado: "Terminado",
      procesado: "Procesado",
    };
    const clase = value === "procesado" ? "ok" : value === "terminado" ? "info" : "warn";
    return `<span class="badge ${clase}">${esc(etiquetas[value] || value || "—")}</span>`;
  }

  function stockBadge(cantidad) {
    const n = Number(cantidad);
    if (!Number.isFinite(n)) return `<span class="badge">—</span>`;
    if (n <= 0) return `<span class="badge danger">Sin stock</span>`;
    if (n < 12) return `<span class="badge warn">${numberText(n)} u.</span>`;
    return `<span class="badge ok">${numberText(n)} u.</span>`;
  }

  function setView(html) {
    view.innerHTML = html;
  }

  function loadingHtml(texto = "Consultando la base…") {
    return `<div class="loading"><span class="spinner" aria-hidden="true"></span><span>${esc(texto)}</span></div>`;
  }

  function errorHtml(error) {
    const regla = error && error.regla ? `<p class="small mono">Regla: ${esc(error.regla)}</p>` : "";
    return `
      <div class="error-box" role="alert">
        <strong>No se pudo completar la operación</strong>
        <p>${esc(error && error.message ? error.message : "Error inesperado")}</p>
        ${regla}
      </div>`;
  }

  function showToast(message, type = "") {
    if (!toastBox) return;
    toastBox.textContent = message;
    toastBox.className = `toast ${type}`.trim();
    toastBox.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toastBox.hidden = true;
    }, 5200);
  }

  function setStatus(ok, label) {
    if (!statusChip) return;
    statusChip.classList.toggle("ok", ok === true);
    statusChip.classList.toggle("error", ok === false);
    const text = statusChip.querySelector(".status-label");
    if (text) text.textContent = label;
  }

  async function checkHealth() {
    setStatus(null, "Verificando API…");
    try {
      const salud = await api("/salud");
      const ok = salud && salud.status === "ok" && salud.base_de_datos === "ok";
      setStatus(ok, ok ? `API y base OK · ${salud.current_user}` : "API con problemas");
      return salud;
    } catch (error) {
      setStatus(false, "API no disponible");
      return null;
    }
  }

  function parseHash() {
    const raw = window.location.hash.replace(/^#\/?/, "");
    const [routeRaw, queryRaw = ""] = raw.split("?", 2);
    const fijas = ["inicio", "vinos", "clientes", "ventas", "stock", "reportes"];
    const route = fijas.includes(routeRaw) || /^comprobantes\/\d+$/.test(routeRaw)
      ? routeRaw
      : "inicio";
    return { route, params: new URLSearchParams(queryRaw) };
  }

  function setActiveNav(route) {
    document.querySelectorAll(".main-nav a[data-route]").forEach((link) => {
      const active = link.dataset.route === route;
      link.classList.toggle("active", active);
      if (active) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    });
  }

  function formValue(form, name) {
    const element = form.elements.namedItem(name);
    if (!element) return "";
    return String(element.value || "").trim();
  }

  function formNumber(form, name) {
    const valor = formValue(form, name);
    if (valor === "") return null;
    const numero = Number(valor);
    return Number.isFinite(numero) ? numero : null;
  }

  function pageHead(kicker, title, description, actions = "") {
    return `
      <div class="page-head">
        <div>
          <p class="eyebrow">${esc(kicker)}</p>
          <h2>${esc(title)}</h2>
          <p>${esc(description)}</p>
        </div>
        ${actions ? `<div class="actions" style="margin-top:0">${actions}</div>` : ""}
      </div>`;
  }

  function emptyHtml(texto) {
    return `<div class="empty">${esc(texto)}</div>`;
  }

  // -----------------------------------------------------------------------
  // Inicio
  // -----------------------------------------------------------------------
  async function showInicio() {
    const token = ++renderToken;
    setView(`
      <section class="hero">
        <div>
          <p class="eyebrow">Sistema de gestión</p>
          <h2>La bodega, sus vinos y su red comercial en un solo panel.</h2>
          <p>
            Consultá el catálogo, revisá clientes, registrá ventas y movimientos de stock.
            Las reglas de negocio y la auditoría siguen viviendo en PostgreSQL.
          </p>
        </div>
        <div class="hero-actions">
          <a class="button primary" href="#/vinos">Explorar vinos</a>
          <a class="button" href="#/ventas">Registrar venta</a>
        </div>
      </section>
      <div class="stats-grid" id="inicio-stats">
        ${["Catálogo", "Clientes", "Ventas", "Base de datos"]
          .map(
            (label) => `
            <article class="stat-card">
              <p class="stat-label">${label}</p>
              <p class="stat-value">…</p>
              <p class="stat-note">Consultando</p>
            </article>`
          )
          .join("")}
      </div>
      <div class="grid-2 wide-left">
        <section class="card">
          <div class="card-head">
            <div>
              <h3>Ranking de vinos</h3>
              <p class="small muted">S1 · botellas vendidas</p>
            </div>
            <a class="button small" href="#/reportes">Ver reportes</a>
          </div>
          <div id="inicio-ranking">${loadingHtml("Cargando ranking…")}</div>
        </section>
        <section class="card card-accent">
          <h3>Accesos rápidos</h3>
          <p class="small muted">Operaciones frecuentes sobre la API de la Etapa 6.</p>
          <div class="actions">
            <a class="button" href="#/vinos">Vinos</a>
            <a class="button" href="#/clientes">Clientes</a>
            <a class="button" href="#/stock">Stock</a>
            <a class="button" href="#/reportes">Reportes</a>
          </div>
          <div id="inicio-salud" class="notice" style="margin-top:1rem">Verificando /salud…</div>
        </section>
      </div>`);

    const [salud, vinos, clientes, top] = await Promise.allSettled([
      api("/salud"),
      api("/vinos?page_size=1"),
      api("/clientes?page_size=1"),
      api("/reportes/top-vinos"),
    ]);
    if (token !== renderToken) return;

    const stats = document.querySelectorAll("#inicio-stats .stat-card");
    if (stats.length === 4) {
      const valores = [
        vinos.status === "fulfilled" ? numberText(vinos.value.total) : "—",
        clientes.status === "fulfilled" ? numberText(clientes.value.total) : "—",
        top.status === "fulfilled" ? numberText(top.value.reduce((acc, fila) => acc + Number(fila.botellas_vendidas || 0), 0)) : "—",
        salud.status === "fulfilled" && salud.value.base_de_datos === "ok" ? "OK" : "Revisar",
      ];
      stats.forEach((card, index) => {
        const value = card.querySelector(".stat-value");
        const note = card.querySelector(".stat-note");
        if (value) value.textContent = valores[index];
        if (note) {
          note.textContent = [
            "vinos disponibles",
            "clientes registrados",
            "botellas en el top",
            salud.status === "fulfilled" ? `rol ${salud.value.current_user || "—"}` : "sin conexión",
          ][index];
        }
      });
    }

    const saludBox = document.getElementById("inicio-salud");
    if (saludBox) {
      if (salud.status === "fulfilled") {
        saludBox.innerHTML = `Base conectada como <strong>${esc(salud.value.current_user || "—")}</strong> y API respondiendo.`;
      } else {
        saludBox.innerHTML = "No se pudo verificar /salud. Revisá la conexión o los logs del contenedor.";
      }
    }

    const ranking = document.getElementById("inicio-ranking");
    if (ranking) {
      if (top.status !== "fulfilled" || !Array.isArray(top.value) || top.value.length === 0) {
        ranking.innerHTML = emptyHtml("Todavía no hay ventas registradas para armar el ranking.");
      } else {
        ranking.innerHTML = `
          <ul class="list-clean">
            ${top.value
              .slice(0, 6)
              .map(
                (fila, index) => `
                <li>
                  <span><span class="badge info">${index + 1}</span> <strong>${esc(fila.nombre)}</strong></span>
                  <span class="muted">${numberText(fila.botellas_vendidas)} botellas</span>
                </li>`
              )
              .join("")}
          </ul>`;
      }
    }
  }

  // -----------------------------------------------------------------------
  // Vinos
  // -----------------------------------------------------------------------
  function vinosQuery() {
    const params = new URLSearchParams({
      page: String(state.vinos.page),
      page_size: String(state.vinos.pageSize),
    });
    if (state.vinos.nombre) params.set("nombre", state.vinos.nombre);
    if (state.vinos.tipo) params.set("tipo", state.vinos.tipo);
    if (state.vinos.anada) params.set("anada", state.vinos.anada);
    return params;
  }

  function vinosTable(data) {
    if (!data.items || data.items.length === 0) {
      return emptyHtml("No se encontraron vinos con esos filtros.");
    }
    return `
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Código</th>
              <th>Vino</th>
              <th>Tipo</th>
              <th>Añada</th>
              <th class="num">Precio</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            ${data.items
              .map(
                (vino) => `
                <tr>
                  <td class="mono">${esc(vino.codigo)}</td>
                  <td><strong>${esc(vino.nombre)}</strong></td>
                  <td><span class="badge">${esc(tipoVino(vino.tipo))}</span></td>
                  <td>${esc(vino.anada)}</td>
                  <td class="num">${esc(money(vino.precio))}</td>
                  <td><a class="button small" href="#/vinos?codigo=${encodeURIComponent(vino.codigo)}">Ver ficha</a></td>
                </tr>`
              )
              .join("")}
          </tbody>
        </table>
      </div>`;
  }

  function paginationHtml(data, kind) {
    const actual = Number(data.page || 1);
    const tam = Number(data.page_size || 20);
    const total = Number(data.total || 0);
    const paginas = Math.max(1, Math.ceil(total / tam));
    return `
      <div class="pagination">
        <span>${numberText(total)} registros · página ${actual} de ${paginas}</span>
        <div class="pagination-controls">
          <button class="button small" type="button" id="${kind}-prev" ${actual <= 1 ? "disabled" : ""}>Anterior</button>
          <button class="button small" type="button" id="${kind}-next" ${actual >= paginas ? "disabled" : ""}>Siguiente</button>
        </div>
      </div>`;
  }

  function vinoDetailHtml(vino) {
    const cepas = Array.isArray(vino.cepas) && vino.cepas.length
      ? `<ul class="chips">${vino.cepas.map((cepa) => `<li class="chip">${esc(cepa.nombre)} · ${esc(cepa.porcentaje)}%</li>`).join("")}</ul>`
      : `<p class="small muted">Sin composición cargada.</p>`;
    const maridajes = Array.isArray(vino.maridajes) && vino.maridajes.length
      ? `<ul class="chips">${vino.maridajes.map((m) => `<li class="chip">${esc(m.nombre)} · ${esc(m.temperatura_servicio)} °C</li>`).join("")}</ul>`
      : `<p class="small muted">Sin maridajes cargados.</p>`;

    return `
      <section class="card" id="vino-detalle">
        <div class="detail-hero">
          <div class="card-head">
            <div>
              <p class="eyebrow">Ficha del vino</p>
              <h3>${esc(vino.nombre)}</h3>
              <p>${esc(tipoVino(vino.tipo))} · añada ${esc(vino.anada)} · ${esc(vino.volumen_ml)} ml</p>
            </div>
            <a class="button small" href="#/vinos">Cerrar ficha</a>
          </div>
        </div>
        <div class="metric-row">
          <div class="metric-pill"><span>Depósito</span><strong>${numberText(vino.stock_deposito)}</strong></div>
          <div class="metric-pill"><span>Salas</span><strong>${numberText(vino.stock_sala)}</strong></div>
          <div class="metric-pill"><span>Total</span><strong>${numberText(vino.stock_total)}</strong></div>
        </div>
        <dl class="detail-list" style="margin-top:1rem">
          <div><dt>Precio</dt><dd>${esc(money(vino.precio))}</dd></div>
          <div><dt>Graduación</dt><dd>${esc(vino.graduacion)} %</dd></div>
          <div><dt>Bodega</dt><dd>${esc(vino.bodega.razon_social)} <span class="muted">(${esc(vino.bodega.cuit)})</span></dd></div>
          <div><dt>Domicilio</dt><dd>${esc(vino.bodega.calle)} ${esc(vino.bodega.numero)}</dd></div>
          <div><dt>Cepas</dt><dd>${cepas}</dd></div>
          <div><dt>Maridajes</dt><dd>${maridajes}</dd></div>
        </dl>
        <div class="actions">
          <a class="button primary" href="#/ventas?codigo=${encodeURIComponent(vino.codigo)}">Vender este vino</a>
          <a class="button" href="#/reportes?codigo=${encodeURIComponent(vino.codigo)}">Ver trazabilidad</a>
        </div>
      </section>`;
  }

  async function showVinos(params) {
    const codigo = params.get("codigo");
    state.vinos.selected = codigo ? Number(codigo) : null;
    const token = ++renderToken;
    setView(`
      ${pageHead("Catálogo", "Vinos", "Filtrá el catálogo y abrí la ficha para ver bodega, cepas, maridajes y stock.")}
      <section class="card">
        <form id="filtro-vinos" class="form-grid">
          <div class="field span-5">
            <label for="vino-nombre">Nombre</label>
            <input id="vino-nombre" name="nombre" type="search" placeholder="Ej. Malbec" value="${esc(state.vinos.nombre)}">
          </div>
          <div class="field span-3">
            <label for="vino-tipo">Tipo</label>
            <select id="vino-tipo" name="tipo">
              <option value="">Todos</option>
              ${["tinto", "blanco", "rosado", "espumante"].map((tipo) => `<option value="${tipo}" ${state.vinos.tipo === tipo ? "selected" : ""}>${tipoVino(tipo)}</option>`).join("")}
            </select>
          </div>
          <div class="field span-2">
            <label for="vino-anada">Añada</label>
            <input id="vino-anada" name="anada" type="number" min="1900" max="2100" placeholder="2022" value="${esc(state.vinos.anada)}">
          </div>
          <div class="field span-2">
            <label>&nbsp;</label>
            <button class="button primary" type="submit">Filtrar</button>
          </div>
        </form>
      </section>
      <div class="grid-2 wide-left" style="margin-top:1rem">
        <section class="card" id="vinos-lista">${loadingHtml("Cargando catálogo…")}</section>
        <div id="vinos-detalle">${codigo ? loadingHtml("Cargando ficha…") : `<section class="card card-subtle"><h3>Ficha del vino</h3><p class="small muted">Seleccioná un vino de la tabla para ver su composición, maridajes y stock.</p></section>`}</div>
      </div>`);

    try {
      const data = await api(`/vinos?${vinosQuery().toString()}`);
      if (token !== renderToken) return;
      const lista = document.getElementById("vinos-lista");
      if (lista) {
        lista.innerHTML = `
          ${vinosTable(data)}
          ${paginationHtml(data, "vinos")}`;
        const prev = document.getElementById("vinos-prev");
        const next = document.getElementById("vinos-next");
        if (prev) prev.addEventListener("click", () => {
          if (state.vinos.page > 1) {
            state.vinos.page -= 1;
            showVinos(new URLSearchParams());
          }
        });
        if (next) next.addEventListener("click", () => {
          state.vinos.page += 1;
          showVinos(new URLSearchParams());
        });
      }
    } catch (error) {
      if (token !== renderToken) return;
      const lista = document.getElementById("vinos-lista");
      if (lista) lista.innerHTML = errorHtml(error);
    }

    const form = document.getElementById("filtro-vinos");
    if (form) {
      form.addEventListener("submit", (event) => {
        event.preventDefault();
        state.vinos.nombre = formValue(form, "nombre");
        state.vinos.tipo = formValue(form, "tipo");
        state.vinos.anada = formValue(form, "anada");
        state.vinos.page = 1;
        showVinos(new URLSearchParams());
      });
    }

    if (codigo) {
      try {
        const vino = await api(`/vinos/${encodeURIComponent(codigo)}`);
        if (token !== renderToken) return;
        const detalle = document.getElementById("vinos-detalle");
        if (detalle) detalle.innerHTML = vinoDetailHtml(vino);
      } catch (error) {
        if (token !== renderToken) return;
        const detalle = document.getElementById("vinos-detalle");
        if (detalle) detalle.innerHTML = errorHtml(error);
      }
    }
  }

  // -----------------------------------------------------------------------
  // Clientes
  // -----------------------------------------------------------------------
  function clientesQuery() {
    const params = new URLSearchParams({
      page: String(state.clientes.page),
      page_size: String(state.clientes.pageSize),
    });
    if (state.clientes.tipo) params.set("tipo", state.clientes.tipo);
    if (state.clientes.estado !== "") params.set("estado_activo", state.clientes.estado);
    if (state.clientes.documento) params.set("documento", state.clientes.documento);
    return params;
  }

  function clienteNombre(cliente) {
    if (cliente.razon_social) return cliente.razon_social;
    return [cliente.nombre, cliente.apellido].filter(Boolean).join(" ") || `Cliente ${cliente.id}`;
  }

  function clientesTable(data) {
    if (!data.items || data.items.length === 0) {
      return emptyHtml("No se encontraron clientes con esos filtros.");
    }
    return `
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>ID</th><th>Cliente</th><th>Tipo</th><th>Documento</th><th>Estado</th><th></th></tr>
          </thead>
          <tbody>
            ${data.items
              .map(
                (cliente) => `
                <tr>
                  <td class="mono">${esc(cliente.id)}</td>
                  <td><strong>${esc(clienteNombre(cliente))}</strong><br><span class="small muted">${esc(cliente.calle)} ${esc(cliente.numero)} · CP ${esc(cliente.codigo_postal)}</span></td>
                  <td><span class="badge">${esc(tipoCliente(cliente.tipo))}</span></td>
                  <td>${esc(cliente.tipo_documento)} ${esc(cliente.numero_documento)}</td>
                  <td>${cliente.estado_activo ? `<span class="badge ok">Activo</span>` : `<span class="badge danger">Inactivo</span>`}</td>
                  <td><a class="button small" href="#/clientes?id=${encodeURIComponent(cliente.id)}">Ver ficha</a></td>
                </tr>`
              )
              .join("")}
          </tbody>
        </table>
      </div>`;
  }

  function clienteDetailHtml(cliente) {
    const permisos = Array.isArray(cliente.permisos) && cliente.permisos.length
      ? `<ul class="chips">${cliente.permisos.map((p) => `<li class="chip">${esc(dateText(p.fecha_emision))} → ${esc(dateText(p.fecha_vencimiento))}</li>`).join("")}</ul>`
      : `<span class="muted">Sin permisos de exportación.</span>`;
    return `
      <section class="card" id="cliente-detalle">
        <div class="detail-hero">
          <div class="card-head">
            <div>
              <p class="eyebrow">Ficha del cliente</p>
              <h3>${esc(clienteNombre(cliente))}</h3>
              <p>${esc(tipoCliente(cliente.tipo))} · alta ${esc(dateText(cliente.fecha_alta))}</p>
            </div>
            <a class="button small" href="#/clientes">Cerrar</a>
          </div>
        </div>
        <dl class="detail-list" style="margin-top:1rem">
          <div><dt>ID</dt><dd class="mono">${esc(cliente.id)}</dd></div>
          <div><dt>Documento</dt><dd>${esc(cliente.tipo_documento)} ${esc(cliente.numero_documento)}</dd></div>
          <div><dt>Domicilio</dt><dd>${esc(cliente.calle)} ${esc(cliente.numero)} · CP ${esc(cliente.codigo_postal)}</dd></div>
          <div><dt>Estado</dt><dd>${cliente.estado_activo ? "Activo" : "Inactivo"}</dd></div>
          ${cliente.zona_cobertura ? `<div><dt>Zona</dt><dd>${esc(cliente.zona_cobertura)}</dd></div>` : ""}
          ${cliente.numero_habilitacion ? `<div><dt>Habilitación</dt><dd>${esc(cliente.numero_habilitacion)}</dd></div>` : ""}
          ${cliente.pais_destino ? `<div><dt>País destino</dt><dd>${esc(cliente.pais_destino)}</dd></div>` : ""}
          ${cliente.descuento_especial ? `<div><dt>Descuento</dt><dd>${esc(cliente.descuento_especial)}</dd></div>` : ""}
          <div><dt>Permisos</dt><dd>${permisos}</dd></div>
        </dl>
        <div class="actions">
          <a class="button" href="#/ventas?cliente=${encodeURIComponent(cliente.id)}">Vender a este cliente</a>
          <button class="button danger" type="button" id="cliente-eliminar" data-id="${esc(cliente.id)}">Dar de baja</button>
        </div>
      </section>`;
  }

  function clienteCreateFormHtml() {
    return `
      <details>
        <summary>Registrar un cliente nuevo</summary>
        <div class="details-body">
          <form id="cliente-form" class="form-grid">
            <div class="field span-4">
              <label for="cliente-tipo">Tipo</label>
              <select id="cliente-tipo" name="tipo" required>
                <option value="cliente_comun">Cliente común</option>
                <option value="socio_club">Socio del club</option>
                <option value="distribuidor">Distribuidor</option>
                <option value="exportador">Exportador</option>
              </select>
            </div>
            <div class="field span-4">
              <label for="cliente-nombre">Nombre</label>
              <input id="cliente-nombre" name="nombre" maxlength="60">
            </div>
            <div class="field span-4">
              <label for="cliente-apellido">Apellido</label>
              <input id="cliente-apellido" name="apellido" maxlength="60">
            </div>
            <div class="field span-6">
              <label for="cliente-razon">Razón social</label>
              <input id="cliente-razon" name="razon_social" maxlength="120">
            </div>
            <div class="field span-3">
              <label for="cliente-calle">Calle</label>
              <input id="cliente-calle" name="calle" required maxlength="60">
            </div>
            <div class="field span-3">
              <label for="cliente-numero">Número</label>
              <input id="cliente-numero" name="numero" required maxlength="10">
            </div>
            <div class="field span-2">
              <label for="cliente-cp">Código postal</label>
              <input id="cliente-cp" name="codigo_postal" required minlength="4" maxlength="8">
            </div>
            <div class="field span-2">
              <label for="cliente-tipo-doc">Tipo doc.</label>
              <input id="cliente-tipo-doc" name="tipo_documento" required maxlength="10" value="DNI">
            </div>
            <div class="field span-4">
              <label for="cliente-nro-doc">Número doc.</label>
              <input id="cliente-nro-doc" name="numero_documento" required maxlength="20">
            </div>
            <div class="field span-4">
              <label for="cliente-zona">Zona de cobertura</label>
              <input id="cliente-zona" name="zona_cobertura" maxlength="100" placeholder="Solo distribuidor">
            </div>
            <div class="field span-4">
              <label for="cliente-habilitacion">N° habilitación</label>
              <input id="cliente-habilitacion" name="numero_habilitacion" maxlength="20" placeholder="Solo distribuidor">
            </div>
            <div class="field span-4">
              <label for="cliente-pais">País destino</label>
              <input id="cliente-pais" name="pais_destino" maxlength="50" placeholder="Solo exportador">
            </div>
            <div class="field span-2">
              <label for="cliente-descuento">Descuento</label>
              <input id="cliente-descuento" name="descuento_especial" type="number" min="0" max="1" step="0.01" placeholder="0.10">
            </div>
            <div class="field span-6">
              <label>&nbsp;</label>
              <button class="button primary" type="submit">Crear cliente</button>
            </div>
          </form>
          <p class="help">El alta usa el procedimiento de la base. Para distribuidor/exportador completá los campos específicos; para los demás podés dejarlos vacíos.</p>
        </div>
      </details>`;
  }

  async function showClientes(params) {
    const id = params.get("id");
    state.clientes.selected = id ? Number(id) : null;
    const token = ++renderToken;
    setView(`
      ${pageHead("Red comercial", "Clientes", "Clientes comunes, socios, distribuidores y exportadores con su estado y permisos.")}
      <section class="card">
        <form id="filtro-clientes" class="form-grid">
          <div class="field span-4">
            <label for="cliente-filtro-tipo">Tipo</label>
            <select id="cliente-filtro-tipo" name="tipo">
              <option value="">Todos</option>
              ${["cliente_comun", "socio_club", "distribuidor", "exportador"].map((tipo) => `<option value="${tipo}" ${state.clientes.tipo === tipo ? "selected" : ""}>${tipoCliente(tipo)}</option>`).join("")}
            </select>
          </div>
          <div class="field span-3">
            <label for="cliente-filtro-estado">Estado</label>
            <select id="cliente-filtro-estado" name="estado_activo">
              <option value="">Todos</option>
              <option value="true" ${state.clientes.estado === "true" ? "selected" : ""}>Activos</option>
              <option value="false" ${state.clientes.estado === "false" ? "selected" : ""}>Inactivos</option>
            </select>
          </div>
          <div class="field span-3">
            <label for="cliente-filtro-documento">Documento</label>
            <input id="cliente-filtro-documento" name="documento" type="search" value="${esc(state.clientes.documento)}">
          </div>
          <div class="field span-2">
            <label>&nbsp;</label>
            <button class="button primary" type="submit">Filtrar</button>
          </div>
        </form>
      </section>
      <div class="grid-2 wide-left" style="margin-top:1rem">
        <section class="card" id="clientes-lista">${loadingHtml("Cargando clientes…")}</section>
        <div id="clientes-detalle">${id ? loadingHtml("Cargando ficha…") : `<section class="card card-subtle"><h3>Ficha del cliente</h3><p class="small muted">Seleccioná un cliente para ver sus datos y permisos.</p></section>`}</div>
      </div>
      <div style="margin-top:1rem">${clienteCreateFormHtml()}</div>`);

    try {
      const data = await api(`/clientes?${clientesQuery().toString()}`);
      if (token !== renderToken) return;
      const lista = document.getElementById("clientes-lista");
      if (lista) {
        lista.innerHTML = `${clientesTable(data)}${paginationHtml(data, "clientes")}`;
        const prev = document.getElementById("clientes-prev");
        const next = document.getElementById("clientes-next");
        if (prev) prev.addEventListener("click", () => {
          if (state.clientes.page > 1) {
            state.clientes.page -= 1;
            showClientes(new URLSearchParams());
          }
        });
        if (next) next.addEventListener("click", () => {
          state.clientes.page += 1;
          showClientes(new URLSearchParams());
        });
      }
    } catch (error) {
      if (token !== renderToken) return;
      const lista = document.getElementById("clientes-lista");
      if (lista) lista.innerHTML = errorHtml(error);
    }

    const form = document.getElementById("filtro-clientes");
    if (form) {
      form.addEventListener("submit", (event) => {
        event.preventDefault();
        state.clientes.tipo = formValue(form, "tipo");
        state.clientes.estado = formValue(form, "estado_activo");
        state.clientes.documento = formValue(form, "documento");
        state.clientes.page = 1;
        showClientes(new URLSearchParams());
      });
    }

    const createForm = document.getElementById("cliente-form");
    if (createForm) {
      createForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        const payload = {
          tipo: formValue(createForm, "tipo"),
          calle: formValue(createForm, "calle"),
          numero: formValue(createForm, "numero"),
          codigo_postal: formValue(createForm, "codigo_postal"),
          tipo_documento: formValue(createForm, "tipo_documento"),
          numero_documento: formValue(createForm, "numero_documento"),
          permisos: [],
        };
        ["nombre", "apellido", "razon_social", "zona_cobertura", "numero_habilitacion", "pais_destino"].forEach((campo) => {
          const valor = formValue(createForm, campo);
          if (valor) payload[campo] = valor;
        });
        const descuento = formValue(createForm, "descuento_especial");
        if (descuento) payload.descuento_especial = descuento;
        const submit = createForm.querySelector("button[type=submit]");
        if (submit) submit.disabled = true;
        try {
          const creado = await api("/clientes", { method: "POST", body: payload });
          showToast(`Cliente ${creado.id} creado.`, "ok");
          window.location.hash = `#/clientes?id=${creado.id}`;
        } catch (error) {
          showToast(error.message, "error");
        } finally {
          if (submit) submit.disabled = false;
        }
      });
    }

    if (id) {
      try {
        const cliente = await api(`/clientes/${encodeURIComponent(id)}`);
        if (token !== renderToken) return;
        const detalle = document.getElementById("clientes-detalle");
        if (detalle) detalle.innerHTML = clienteDetailHtml(cliente);
        const eliminar = document.getElementById("cliente-eliminar");
        if (eliminar) {
          eliminar.addEventListener("click", async () => {
            if (!window.confirm(`¿Dar de baja al cliente ${id}? La base rechazará la operación si tiene comprobantes.`)) return;
            eliminar.disabled = true;
            try {
              await api(`/clientes/${encodeURIComponent(id)}`, { method: "DELETE" });
              showToast("Cliente dado de baja.", "ok");
              window.location.hash = "#/clientes";
            } catch (error) {
              showToast(error.message, "error");
              eliminar.disabled = false;
            }
          });
        }
      } catch (error) {
        if (token !== renderToken) return;
        const detalle = document.getElementById("clientes-detalle");
        if (detalle) detalle.innerHTML = errorHtml(error);
      }
    }
  }

  // -----------------------------------------------------------------------
  // Ventas
  // -----------------------------------------------------------------------
  async function loadClientesParaVenta() {
    if (state.ventas.clientes.length) return state.ventas.clientes;
    try {
      const data = await api("/clientes?page_size=100");
      state.ventas.clientes = Array.isArray(data.items) ? data.items : [];
    } catch (error) {
      state.ventas.clientes = [];
    }
    return state.ventas.clientes;
  }

  function comprobanteHtml(comprobante) {
    return `
      <section class="card card-accent" id="venta-resultado">
        <div class="card-head">
          <div>
            <p class="eyebrow">Venta registrada</p>
            <h3>Comprobante #${esc(comprobante.numero)}</h3>
            <p class="small muted">${esc(dateText(comprobante.fecha))} · sala ${esc(comprobante.sala.id)}</p>
          </div>
          <a class="button small" href="#/comprobantes/${encodeURIComponent(comprobante.numero)}" data-comprobante="${esc(comprobante.numero)}">Ver detalle</a>
        </div>
        <div class="metric-row">
          <div class="metric-pill"><span>Subtotal</span><strong>${esc(money(comprobante.subtotal))}</strong></div>
          <div class="metric-pill"><span>Descuento</span><strong>${esc(money(comprobante.descuento_total))}</strong></div>
          <div class="metric-pill"><span>Total</span><strong>${esc(money(comprobante.total))}</strong></div>
        </div>
        <p class="small muted" style="margin-top:0.75rem">Cliente: ${esc(clienteNombre(comprobante.cliente))}</p>
        <div class="table-wrap" style="margin-top:0.75rem">
          <table>
            <thead><tr><th>Vino</th><th class="num">Cantidad</th><th class="num">Precio unit.</th><th class="num">Subtotal</th></tr></thead>
            <tbody>
              ${(comprobante.renglones || []).map((r) => `
                <tr>
                  <td>${esc(r.nombre_vino)}</td>
                  <td class="num">${numberText(r.cantidad)}</td>
                  <td class="num">${esc(money(r.precio_unitario))}</td>
                  <td class="num">${esc(money(r.subtotal_renglon))}</td>
                </tr>`).join("")}
            </tbody>
          </table>
        </div>
      </section>`;
  }

  async function showVentas(params) {
    const token = ++renderToken;
    const prefillCode = params.get("codigo");
    const prefillCliente = params.get("cliente");
    if (prefillCode) {
      state.ventas.prefill = { codigo: Number(prefillCode), cliente: prefillCliente };
    } else if (prefillCliente) {
      state.ventas.prefill = { codigo: state.ventas.prefill ? state.ventas.prefill.codigo : null, cliente: prefillCliente };
    }
    const resultado = state.ventas.result;
    setView(`
      ${pageHead("Operaciones", "Registrar venta", "La API inserta la cabecera y los renglones; los totales, descuentos y stock los calcula PostgreSQL.")}
      <div class="grid-2 wide-left">
        <section class="card">
          <div class="card-head">
            <div><h3>Nueva venta</h3><p class="small muted">Los IDs se pueden consultar en las fichas de clientes y vinos.</p></div>
            <a class="button small" href="#/clientes">Buscar cliente</a>
          </div>
          <form id="venta-form" class="form-grid">
            <div class="field span-6">
              <label for="venta-cliente">ID cliente</label>
              <input id="venta-cliente" name="id_cliente" type="number" min="1" required list="clientes-datalist" value="${esc(prefillCliente || "")}">
              <datalist id="clientes-datalist"></datalist>
            </div>
            <div class="field span-3">
              <label for="venta-sala">ID sala</label>
              <input id="venta-sala" name="id_sala_venta" type="number" min="1" required>
            </div>
            <div class="field span-3">
              <label for="venta-fecha">Fecha</label>
              <input id="venta-fecha" name="fecha" type="date">
            </div>
            <div class="field span-6">
              <label for="venta-vino">Código de vino</label>
              <input id="venta-vino" name="codigo_vino" type="number" min="1" required value="${esc(prefillCode || "")}">
            </div>
            <div class="field span-3">
              <label for="venta-cantidad">Cantidad</label>
              <input id="venta-cantidad" name="cantidad" type="number" min="1" required value="1">
            </div>
            <div class="field span-3">
              <label>&nbsp;</label>
              <button class="button primary" type="submit">Registrar venta</button>
            </div>
          </form>
          <div id="venta-error" style="margin-top:0.8rem"></div>
          <p class="help" style="margin-top:0.8rem">Si el stock no alcanza, la base devuelve 409 y la transacción completa se revierte.</p>
        </section>
        <div id="venta-resultado-wrap">${resultado ? comprobanteHtml(resultado) : `<section class="card card-subtle"><h3>Resultado</h3><p class="small muted">La venta registrada aparecerá acá con sus totales calculados por la base.</p></section>`}</div>
      </div>`);

    const clientes = await loadClientesParaVenta();
    if (token !== renderToken) return;
    const datalist = document.getElementById("clientes-datalist");
    if (datalist) {
      datalist.innerHTML = clientes
        .map((c) => `<option value="${esc(c.id)}">${esc(clienteNombre(c))} · ${esc(tipoCliente(c.tipo))}</option>`)
        .join("");
    }

    const form = document.getElementById("venta-form");
    if (form) {
      form.addEventListener("submit", async (event) => {
        event.preventDefault();
        const errorBox = document.getElementById("venta-error");
        if (errorBox) errorBox.innerHTML = "";
        const payload = {
          id_cliente: formNumber(form, "id_cliente"),
          id_sala_venta: formNumber(form, "id_sala_venta"),
          renglones: [{ codigo_vino: formNumber(form, "codigo_vino"), cantidad: formNumber(form, "cantidad") }],
        };
        const fecha = formValue(form, "fecha");
        if (fecha) payload.fecha = fecha;
        const submit = form.querySelector("button[type=submit]");
        if (submit) submit.disabled = true;
        try {
          const comprobante = await api("/comprobantes", { method: "POST", body: payload });
          state.ventas.result = comprobante;
          showToast(`Venta registrada: comprobante #${comprobante.numero}.`, "ok");
          await showVentas(new URLSearchParams());
        } catch (error) {
          if (errorBox) errorBox.innerHTML = errorHtml(error);
          showToast(error.message, "error");
        } finally {
          if (submit) submit.disabled = false;
        }
      });
    }

    const comprobanteLink = document.querySelector("[data-comprobante]");
    if (comprobanteLink) {
      comprobanteLink.addEventListener("click", (event) => {
        event.preventDefault();
        showComprobante(Number(comprobanteLink.dataset.comprobante));
      });
    }
  }

  async function showComprobante(numero) {
    const token = ++renderToken;
    setView(`
      ${pageHead("Ventas", `Comprobante #${esc(numero)}`, "Detalle con totales, descuento, cliente, sala y renglones calculados por la base.")}
      <div id="comprobante-detalle">${loadingHtml("Cargando comprobante…")}</div>
      <div class="actions"><a class="button" href="#/ventas">Volver a ventas</a></div>`);
    try {
      const comprobante = await api(`/comprobantes/${encodeURIComponent(numero)}`);
      if (token !== renderToken) return;
      const detalle = document.getElementById("comprobante-detalle");
      if (detalle) detalle.innerHTML = comprobanteHtml(comprobante);
    } catch (error) {
      if (token !== renderToken) return;
      const detalle = document.getElementById("comprobante-detalle");
      if (detalle) detalle.innerHTML = errorHtml(error);
    }
  }

  // -----------------------------------------------------------------------
  // Stock
  // -----------------------------------------------------------------------
  function movimientoResultHtml(tipo, pasos, error) {
    return `
      <section class="card ${error ? "" : "card-accent"}">
        <div class="card-head">
          <div><h3>${esc(tipo)}</h3><p class="small muted">Resultado del flujo</p></div>
          ${error ? `<span class="badge danger">Con error</span>` : `<span class="badge ok">Completado</span>`}
        </div>
        <ul class="list-clean">
          ${pasos.map((paso) => `<li><span>${esc(paso.texto)}</span><span class="badge ${paso.ok ? "ok" : "danger"}">${paso.ok ? "OK" : "ERROR"}</span></li>`).join("")}
        </ul>
        ${error ? errorHtml(error) : ""}
      </section>`;
  }

  async function showStock() {
    const token = ++renderToken;
    setView(`
      ${pageHead("Logística", "Stock", "Ingresos al depósito y transferencias a salas. Cada paso se ejecuta contra la API y la base valida el stock.")}
      <div class="grid-2">
        <section class="card">
          <div class="card-head"><div><h3>Ingreso al depósito</h3><p class="small muted">Crea, agrega un renglón, termina y procesa.</p></div></div>
          <form id="ingreso-form" class="form-grid">
            <div class="field span-6"><label for="ingreso-transportista">Código transportista</label><input id="ingreso-transportista" name="codigo_transportista" type="number" min="1" required></div>
            <div class="field span-6"><label for="ingreso-cuit">CUIT bodega</label><input id="ingreso-cuit" name="cuit_bodega" required minlength="11" maxlength="11" placeholder="11 dígitos"></div>
            <div class="field span-6"><label for="ingreso-vino">Código de vino</label><input id="ingreso-vino" name="codigo_vino" type="number" min="1" required></div>
            <div class="field span-3"><label for="ingreso-cantidad">Cantidad</label><input id="ingreso-cantidad" name="cantidad" type="number" min="1" required value="10"></div>
            <div class="field span-3"><label>&nbsp;</label><button class="button primary" type="submit">Procesar ingreso</button></div>
          </form>
          <div id="ingreso-resultado" style="margin-top:0.8rem"></div>
        </section>
        <section class="card">
          <div class="card-head"><div><h3>Transferencia a sala</h3><p class="small muted">Crea, agrega un renglón, termina y procesa.</p></div></div>
          <form id="transferencia-form" class="form-grid">
            <div class="field span-6"><label for="trans-sala">ID sala destino</label><input id="trans-sala" name="id_sala_venta" type="number" min="1" required></div>
            <div class="field span-6"><label for="trans-vino">Código de vino</label><input id="trans-vino" name="codigo_vino" type="number" min="1" required></div>
            <div class="field span-6"><label for="trans-cantidad">Cantidad</label><input id="trans-cantidad" name="cantidad" type="number" min="1" required value="5"></div>
            <div class="field span-6"><label>&nbsp;</label><button class="button primary" type="submit">Procesar transferencia</button></div>
          </form>
          <div id="transferencia-resultado" style="margin-top:0.8rem"></div>
        </section>
      </div>
      <section class="card card-subtle" style="margin-top:1rem">
        <h3>¿Qué hace cada paso?</h3>
        <p class="small muted">La API solo envía las operaciones. Los triggers y procedimientos de PostgreSQL controlan estados, stock negativo, cantidades y transiciones. Si un paso falla, se muestra el error y los pasos anteriores quedan registrados en la base.</p>
      </section>`);

    const ingresoForm = document.getElementById("ingreso-form");
    if (ingresoForm) {
      ingresoForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        const pasos = [];
        const contenedor = document.getElementById("ingreso-resultado");
        const submit = ingresoForm.querySelector("button[type=submit]");
        if (submit) submit.disabled = true;
        try {
          const ingreso = await api("/ingresos", {
            method: "POST",
            body: {
              codigo_transportista: formNumber(ingresoForm, "codigo_transportista"),
              cuit_bodega: formValue(ingresoForm, "cuit_bodega"),
            },
          });
          pasos.push({ texto: `Ingreso #${ingreso.codigo} creado`, ok: true });
          const conRenglon = await api(`/ingresos/${encodeURIComponent(ingreso.codigo)}/renglones`, {
            method: "POST",
            body: { codigo_vino: formNumber(ingresoForm, "codigo_vino"), cantidad: formNumber(ingresoForm, "cantidad") },
          });
          pasos.push({ texto: `Renglón agregado (${conRenglon.renglones.length} en total)`, ok: true });
          await api(`/ingresos/${encodeURIComponent(ingreso.codigo)}/terminar`, { method: "POST" });
          pasos.push({ texto: "Ingreso terminado", ok: true });
          const procesado = await api(`/ingresos/${encodeURIComponent(ingreso.codigo)}/procesar`, { method: "POST" });
          pasos.push({ texto: `Ingreso procesado · ${procesado.codigo}`, ok: true });
          if (contenedor) contenedor.innerHTML = movimientoResultHtml("Ingreso al depósito", pasos, null);
          showToast("Ingreso procesado y stock actualizado.", "ok");
        } catch (error) {
          pasos.push({ texto: "Flujo interrumpido", ok: false });
          if (contenedor) contenedor.innerHTML = movimientoResultHtml("Ingreso al depósito", pasos, error);
          showToast(error.message, "error");
        } finally {
          if (submit) submit.disabled = false;
        }
      });
    }

    const transferenciaForm = document.getElementById("transferencia-form");
    if (transferenciaForm) {
      transferenciaForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        const pasos = [];
        const contenedor = document.getElementById("transferencia-resultado");
        const submit = transferenciaForm.querySelector("button[type=submit]");
        if (submit) submit.disabled = true;
        try {
          const transferencia = await api("/transferencias", {
            method: "POST",
            body: { id_sala_venta: formNumber(transferenciaForm, "id_sala_venta") },
          });
          pasos.push({ texto: `Transferencia #${transferencia.numero} creada`, ok: true });
          const conRenglon = await api(`/transferencias/${encodeURIComponent(transferencia.numero)}/renglones`, {
            method: "POST",
            body: { codigo_vino: formNumber(transferenciaForm, "codigo_vino"), cantidad: formNumber(transferenciaForm, "cantidad") },
          });
          pasos.push({ texto: `Renglón agregado (${conRenglon.renglones.length} en total)`, ok: true });
          await api(`/transferencias/${encodeURIComponent(transferencia.numero)}/terminar`, { method: "POST" });
          pasos.push({ texto: "Transferencia terminada", ok: true });
          const procesada = await api(`/transferencias/${encodeURIComponent(transferencia.numero)}/procesar`, { method: "POST" });
          pasos.push({ texto: `Transferencia procesada · ${procesada.numero}`, ok: true });
          if (contenedor) contenedor.innerHTML = movimientoResultHtml("Transferencia a sala", pasos, null);
          showToast("Transferencia procesada y stock actualizado.", "ok");
        } catch (error) {
          pasos.push({ texto: "Flujo interrumpido", ok: false });
          if (contenedor) contenedor.innerHTML = movimientoResultHtml("Transferencia a sala", pasos, error);
          showToast(error.message, "error");
        } finally {
          if (submit) submit.disabled = false;
        }
      });
    }
  }

  // -----------------------------------------------------------------------
  // Reportes
  // -----------------------------------------------------------------------
  async function showReportes(params) {
    const token = ++renderToken;
    const codigoTraza = params.get("codigo");
    setView(`
      ${pageHead("Consultas", "Reportes", "Rankings, ventas por sala, alertas de stock y trazabilidad del vino.")}
      <div class="grid-2">
        <section class="card report-card" id="reporte-top"><h4>Vinos más vendidos</h4>${loadingHtml("Cargando…")}</section>
        <section class="card report-card" id="reporte-salas"><h4>Ventas por sala</h4>${loadingHtml("Cargando…")}</section>
      </div>
      <div class="grid-2" style="margin-top:1rem">
        <section class="card report-card" id="reporte-transportista"><h4>Transportista activo</h4>${loadingHtml("Cargando…")}</section>
        <section class="card report-card">
          <h4>Vinos sin stock en una sala</h4>
          <form id="reporte-sin-stock" class="form-grid" style="margin-top:0.7rem">
            <div class="field span-8"><label for="reporte-sala">ID sala</label><input id="reporte-sala" name="sala" type="number" min="1" required></div>
            <div class="field span-4"><label>&nbsp;</label><button class="button primary" type="submit">Consultar</button></div>
          </form>
          <div id="reporte-sin-stock-resultado" style="margin-top:0.8rem"></div>
        </section>
      </div>
      <section class="card" style="margin-top:1rem">
        <div class="card-head">
          <div><h4>Trazabilidad del vino</h4><p class="small muted">S9 · bodega, cepas, maridajes y stock total</p></div>
        </div>
        <form id="reporte-traza" class="form-grid">
          <div class="field span-6"><label for="traza-codigo">Código de vino</label><input id="traza-codigo" name="codigo" type="number" min="1" required value="${esc(codigoTraza || "")}"></div>
          <div class="field span-3"><label>&nbsp;</label><button class="button primary" type="submit">Ver ficha</button></div>
        </form>
        <div id="traza-resultado" style="margin-top:0.8rem">${codigoTraza ? loadingHtml("Cargando trazabilidad…") : ""}</div>
      </section>`);

    const [top, salas, transportista] = await Promise.allSettled([
      api("/reportes/top-vinos"),
      api("/reportes/ventas-por-sala"),
      api("/reportes/transportista-activo"),
    ]);
    if (token !== renderToken) return;

    const topBox = document.getElementById("reporte-top");
    if (topBox) {
      if (top.status !== "fulfilled" || !top.value.length) {
        topBox.innerHTML = `<h4>Vinos más vendidos</h4>${emptyHtml("Sin ventas registradas.")}`;
      } else {
        topBox.innerHTML = `
          <h4>Vinos más vendidos</h4>
          <ul class="list-clean" style="margin-top:0.5rem">
            ${top.value.map((fila, i) => `<li><span><span class="badge info">${i + 1}</span> ${esc(fila.nombre)}</span><strong>${numberText(fila.botellas_vendidas)}</strong></li>`).join("")}
          </ul>`;
      }
    }

    const salasBox = document.getElementById("reporte-salas");
    if (salasBox) {
      if (salas.status !== "fulfilled" || !salas.value.length) {
        salasBox.innerHTML = `<h4>Ventas por sala</h4>${emptyHtml("Sin ventas en el último trimestre.")}`;
      } else {
        salasBox.innerHTML = `
          <h4>Ventas por sala</h4>
          <div class="table-wrap" style="margin-top:0.5rem">
            <table><thead><tr><th>Sala</th><th class="num">Monto</th></tr></thead><tbody>
              ${salas.value.map((fila) => `<tr><td>${esc(fila.calle)} ${esc(fila.numero)} <span class="muted">(#${esc(fila.id_sala)})</span></td><td class="num">${esc(money(fila.monto_total))}</td></tr>`).join("")}
            </tbody></table>
          </div>`;
      }
    }

    const transBox = document.getElementById("reporte-transportista");
    if (transBox) {
      if (transportista.status !== "fulfilled" || !transportista.value) {
        transBox.innerHTML = `<h4>Transportista activo</h4>${emptyHtml("Sin actividad en el último mes.")}`;
      } else {
        const t = transportista.value;
        transBox.innerHTML = `
          <h4>Transportista activo</h4>
          <div class="detail-hero" style="margin-top:0.6rem">
            <h3>${esc(t.razon_social)}</h3>
            <p>Código ${esc(t.codigo)} · ${numberText(t.ingresos)} ingresos · ${numberText(t.botellas)} botellas</p>
          </div>`;
      }
    }

    const sinStockForm = document.getElementById("reporte-sin-stock");
    if (sinStockForm) {
      sinStockForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        const box = document.getElementById("reporte-sin-stock-resultado");
        const sala = formValue(sinStockForm, "sala");
        if (box) box.innerHTML = loadingHtml("Consultando…");
        try {
          const data = await api(`/reportes/vinos-sin-stock?sala=${encodeURIComponent(sala)}`);
          if (box) {
            box.innerHTML = data.length
              ? `<ul class="list-clean">${data.map((vino) => `<li><span>${esc(vino.nombre)} <span class="muted">(#${esc(vino.codigo)})</span></span><span class="badge warn">Depósito: ${numberText(vino.stock_deposito)}</span></li>`).join("")}</ul>`
              : emptyHtml("No hay vinos en esa situación.");
          }
        } catch (error) {
          if (box) box.innerHTML = errorHtml(error);
        }
      });
    }

    const trazaForm = document.getElementById("reporte-traza");
    async function cargarTraza(codigo) {
      const box = document.getElementById("traza-resultado");
      if (box) box.innerHTML = loadingHtml("Consultando…");
      try {
        const data = await api(`/reportes/trazabilidad/${encodeURIComponent(codigo)}`);
        if (box) {
          box.innerHTML = `
            <div class="detail-hero">
              <h3>${esc(data.nombre)}</h3>
              <p>${esc(data.bodega)} · stock total ${numberText(data.stock_total)} u.</p>
            </div>
            <dl class="detail-list" style="margin-top:0.8rem">
              <div><dt>Cepas</dt><dd>${esc(data.cepas || "Sin composición")}</dd></div>
              <div><dt>Maridajes</dt><dd>${esc(data.maridajes || "Sin maridajes")}</dd></div>
            </dl>`;
        }
      } catch (error) {
        if (box) box.innerHTML = errorHtml(error);
      }
    }
    if (trazaForm) {
      trazaForm.addEventListener("submit", (event) => {
        event.preventDefault();
        cargarTraza(formValue(trazaForm, "codigo"));
      });
    }
    if (codigoTraza) cargarTraza(codigoTraza);
  }

  // -----------------------------------------------------------------------
  // Router
  // -----------------------------------------------------------------------
  async function render() {
    const { route, params } = parseHash();
    state.route = route;
    state.params = params;
    setActiveNav(route);
    window.scrollTo({ top: 0, behavior: "auto" });

    if (route === "inicio") return showInicio();
    if (route === "vinos") return showVinos(params);
    if (route === "clientes") return showClientes(params);
    if (route === "ventas") return showVentas(params);
    if (route === "stock") return showStock();
    if (route === "reportes") return showReportes(params);
    if (route.startsWith("comprobantes/")) {
      return showComprobante(Number(route.split("/")[1]));
    }
    return showInicio();
  }

  window.addEventListener("hashchange", () => {
    render();
  });

  document.addEventListener("DOMContentLoaded", () => {
    if (!window.location.hash) {
      window.location.replace("#/inicio");
    }
    checkHealth();
    render();
    setInterval(checkHealth, 60000);
  });
})();
