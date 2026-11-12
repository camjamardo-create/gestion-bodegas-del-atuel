#!/usr/bin/env python3
"""Genera la presentación de la Etapa 9 con python-pptx."""

from __future__ import annotations

import re
from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "Bodegas_del_Atuel_Etapa9.pptx"

# ---------------------------------------------------------------------------
# Paleta y tipografías
# ---------------------------------------------------------------------------

BG = RGBColor(0xF6, 0xF1, 0xE7)
WHITE = RGBColor(0xFF, 0xFD, 0xF9)
CREAM = RGBColor(0xEF, 0xE7, 0xD9)
DARK = RGBColor(0x4A, 0x10, 0x20)
DARK_SOFT = RGBColor(0x63, 0x1B, 0x2C)
GOLD = RGBColor(0xB0, 0x7A, 0x3A)
GOLD_LIGHT = RGBColor(0xD9, 0xB5, 0x7A)
GREEN = RGBColor(0x2E, 0x6B, 0x4F)
BODY = RGBColor(0x3A, 0x33, 0x2C)
MUTED = RGBColor(0x77, 0x6C, 0x60)
LINE = RGBColor(0xD9, 0xCF, 0xBE)

CODE_BG = RGBColor(0x1F, 0x1B, 0x18)
CODE_FG = RGBColor(0xF4, 0xEF, 0xE6)
CODE_KEY = RGBColor(0xE7, 0xC2, 0x7D)
CODE_STR = RGBColor(0xA8, 0xD5, 0xBA)
CODE_COM = RGBColor(0x8F, 0xA9, 0x8F)
CODE_NUM = RGBColor(0x9C, 0xC7, 0xE8)

FONT_TITLE = "Cambria"
FONT_BODY = "Segoe UI"
FONT_CODE = "Consolas"

W = 13.333
H = 7.5

KEYWORDS = {
    "ADD", "AFTER", "ALL", "ALTER", "AND", "AS", "BEFORE", "BEGIN", "BY",
    "CALL", "CHECK", "COLUMN", "CONFLICT", "CONSTRAINT", "CREATE", "DECLARE",
    "DEFAULT", "DELETE", "DO", "EACH", "ELSE", "END", "EXCEPTION", "EXECUTE",
    "EXISTS", "FOR", "FOREIGN", "FROM", "FUNCTION", "GRANT", "GROUP", "IF",
    "IN", "INCLUDE", "INDEX", "INSERT", "INTO", "IS", "JOIN", "KEY", "LANGUAGE",
    "LEFT", "LOGIN", "NEW", "NOT", "NULL", "ON", "OR", "ORDER", "PRIMARY",
    "PROCEDURE", "RAISE", "REFERENCES", "REPLACE", "RETURN", "RETURNS", "ROLE",
    "ROW", "SCHEMA", "SELECT", "SET", "TABLE", "THEN", "TO", "TRIGGER", "UNIQUE",
    "UPDATE", "USING", "VALUES", "VIEW", "WHERE", "WITH",
}


def _rgb(hex_value: str) -> RGBColor:
    hex_value = hex_value.lstrip("#")
    return RGBColor(int(hex_value[0:2], 16), int(hex_value[2:4], 16), int(hex_value[4:6], 16))


def set_bg(slide, color: RGBColor) -> None:
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = color


def textbox(
    slide,
    x: float,
    y: float,
    w: float,
    h: float,
    text: str = "",
    size: float = 16,
    color: RGBColor = BODY,
    bold: bool = False,
    italic: bool = False,
    font: str = FONT_BODY,
    align=PP_ALIGN.LEFT,
    anchor=MSO_ANCHOR.TOP,
    line_spacing: float = 1.0,
    margins: tuple[float, float, float, float] = (0, 0, 0, 0),
):
    box = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(margins[0])
    tf.margin_right = Inches(margins[1])
    tf.margin_top = Inches(margins[2])
    tf.margin_bottom = Inches(margins[3])
    tf.vertical_anchor = anchor
    p = tf.paragraphs[0]
    p.alignment = align
    p.line_spacing = line_spacing
    run = p.add_run()
    run.text = text
    run.font.name = font
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = color
    return box


def add_rich_runs(p, text: str, size: float, color: RGBColor, font: str = FONT_BODY):
    """Agrega texto con **negrita** y `código` embebidos."""
    parts = re.split(r"(\*\*.*?\*\*|`.*?`)", text)
    for part in parts:
        if not part:
            continue
        run = p.add_run()
        if part.startswith("**") and part.endswith("**"):
            run.text = part[2:-2]
            run.font.bold = True
            run.font.color.rgb = DARK
            run.font.name = font
        elif part.startswith("`") and part.endswith("`"):
            run.text = part[1:-1]
            run.font.name = FONT_CODE
            run.font.color.rgb = DARK_SOFT
        else:
            run.text = part
            run.font.color.rgb = color
            run.font.name = font
        run.font.size = Pt(size)


def bullets(
    slide,
    x: float,
    y: float,
    w: float,
    h: float,
    items: list[str],
    size: float = 16,
    color: RGBColor = BODY,
    space: float = 9,
    bullet_color: RGBColor = GOLD,
) -> None:
    box = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    for index, item in enumerate(items):
        p = tf.paragraphs[0] if index == 0 else tf.add_paragraph()
        p.line_spacing = 1.05
        p.space_after = Pt(space)
        sub = item.startswith("- ")
        text = item[2:] if sub else item
        r = p.add_run()
        r.text = ("–  " if sub else "•  ")
        r.font.name = FONT_BODY
        r.font.size = Pt(size)
        r.font.color.rgb = bullet_color if not sub else MUTED
        add_rich_runs(p, text, size, color)


def header(slide, kicker: str, title: str, dark: bool = False) -> None:
    k_color = GOLD_LIGHT if dark else GOLD
    t_color = WHITE if dark else DARK
    textbox(slide, 0.75, 0.34, 7.0, 0.28, kicker.upper(), 10, k_color, True, font=FONT_BODY)
    textbox(slide, 0.75, 0.62, 11.8, 0.62, title, 29, t_color, True, font=FONT_TITLE)
    line = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.75), Inches(1.28), Inches(1.15), Inches(0.045))
    line.fill.solid()
    line.fill.fore_color.rgb = GOLD
    line.line.fill.background()


def footer(slide, number: int, source: str | None = None) -> None:
    line = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.75), Inches(7.02), Inches(11.85), Inches(0.012))
    line.fill.solid()
    line.fill.fore_color.rgb = LINE
    line.line.fill.background()
    if source:
        textbox(slide, 0.75, 7.08, 8.4, 0.25, source, 8.5, MUTED, font=FONT_BODY)
    textbox(slide, 9.25, 7.08, 3.35, 0.25, f"Bodegas del Atuel · {number:02d}", 8.5, MUTED, font=FONT_BODY, align=PP_ALIGN.RIGHT)


def code_label(slide, x: float, y: float, text: str, color: RGBColor = GOLD) -> None:
    textbox(slide, x, y, 5.0, 0.24, text.upper(), 8.5, color, True, font=FONT_BODY)


def code_box(
    slide,
    x: float,
    y: float,
    w: float,
    h: float,
    code: str,
    size: float = 10,
    label: str | None = None,
) -> None:
    if label:
        code_label(slide, x, y - 0.26, label)
    rect = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    rect.fill.solid()
    rect.fill.fore_color.rgb = CODE_BG
    rect.line.color.rgb = RGBColor(0x3A, 0x2E, 0x26)
    rect.line.width = Pt(0.75)
    try:
        rect.adjustments[0] = 0.035
        rect.shadow.inherit = False
    except Exception:
        pass

    accent = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(y + 0.16), Inches(0.055), Inches(h - 0.32))
    accent.fill.solid()
    accent.fill.fore_color.rgb = GOLD
    accent.line.fill.background()

    box = slide.shapes.add_textbox(Inches(x + 0.22), Inches(y + 0.13), Inches(w - 0.36), Inches(h - 0.2))
    tf = box.text_frame
    tf.word_wrap = False
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    lines = code.strip("\n").split("\n")
    for index, line in enumerate(lines):
        p = tf.paragraphs[0] if index == 0 else tf.add_paragraph()
        p.line_spacing = 1.0
        p.space_after = Pt(0)
        indent = len(line) - len(line.lstrip(" "))
        line = "\u00A0" * indent + line[indent:]
        if line.strip().startswith("--"):
            r = p.add_run()
            r.text = line
            r.font.name = FONT_CODE
            r.font.size = Pt(size)
            r.font.color.rgb = CODE_COM
            continue
        tokens = re.split(r"(--.*$|'[^']*'|\b[A-Za-z_ÁÉÍÓÚáéíóúñÑ][A-Za-z0-9_ÁÉÍÓÚáéíóúñÑ]*\b|\b\d+(?:[.,]\d+)?\b)", line)
        for token in tokens:
            if not token:
                continue
            r = p.add_run()
            r.text = token
            r.font.name = FONT_CODE
            r.font.size = Pt(size)
            if token.startswith("--"):
                r.font.color.rgb = CODE_COM
            elif token.startswith("'"):
                r.font.color.rgb = CODE_STR
            elif re.fullmatch(r"\d+(?:[.,]\d+)?", token):
                r.font.color.rgb = CODE_NUM
            elif token.upper() in KEYWORDS:
                r.font.color.rgb = CODE_KEY
            else:
                r.font.color.rgb = CODE_FG


def card(
    slide,
    x: float,
    y: float,
    w: float,
    h: float,
    number: str,
    title: str,
    desc: str,
    accent: RGBColor = GOLD,
) -> None:
    rect = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    rect.fill.solid()
    rect.fill.fore_color.rgb = WHITE
    rect.line.color.rgb = LINE
    rect.line.width = Pt(0.75)
    try:
        rect.adjustments[0] = 0.08
        rect.shadow.inherit = False
    except Exception:
        pass
    textbox(slide, x + 0.22, y + 0.14, 0.55, 0.4, number, 18, accent, True, font=FONT_TITLE)
    textbox(slide, x + 0.82, y + 0.14, w - 1.0, 0.32, title, 14.5, DARK, True, font=FONT_BODY)
    textbox(slide, x + 0.82, y + 0.46, w - 1.0, h - 0.52, desc, 11.5, MUTED, font=FONT_BODY, line_spacing=1.05)


def chip(slide, x: float, y: float, w: float, text: str, color: RGBColor = GREEN) -> None:
    rect = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(0.34))
    rect.fill.solid()
    rect.fill.fore_color.rgb = WHITE
    rect.line.color.rgb = color
    rect.line.width = Pt(1)
    textbox(slide, x, y + 0.04, w, 0.26, text, 10.5, color, True, font=FONT_BODY, align=PP_ALIGN.CENTER)


def table(slide, x: float, y: float, w: float, h: float, data: list[list[str]], widths: list[float], size: float = 11.5) -> None:
    rows, cols = len(data), len(data[0])
    shape = slide.shapes.add_table(rows, cols, Inches(x), Inches(y), Inches(w), Inches(h))
    tbl = shape.table
    tbl.first_row = True
    tbl.horz_banding = False
    for i, cw in enumerate(widths):
        tbl.columns[i].width = Inches(cw)
    for r in range(rows):
        tbl.rows[r].height = Inches(h / rows)
        for c in range(cols):
            cell = tbl.cell(r, c)
            cell.fill.solid()
            cell.fill.fore_color.rgb = DARK if r == 0 else (WHITE if r % 2 else CREAM)
            cell.margin_left = Inches(0.08)
            cell.margin_right = Inches(0.08)
            cell.margin_top = Inches(0.03)
            cell.margin_bottom = Inches(0.03)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            tf = cell.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            p.alignment = PP_ALIGN.LEFT if c == 0 else PP_ALIGN.RIGHT
            run = p.add_run()
            run.text = str(data[r][c])
            run.font.name = FONT_BODY
            run.font.size = Pt(size)
            run.font.bold = r == 0
            run.font.color.rgb = WHITE if r == 0 else BODY


def notes(slide, text: str) -> None:
    slide.notes_slide.notes_text_frame.text = text


# ---------------------------------------------------------------------------
# Construcción
# ---------------------------------------------------------------------------

prs = Presentation()
prs.slide_width = Inches(W)
prs.slide_height = Inches(H)
blank = prs.slide_layouts[6]

# ---------------------------------------------------------------------------
# 1. Portada
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, DARK)

band = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(9.15), Inches(0), Inches(4.18), Inches(7.5))
band.fill.solid()
band.fill.fore_color.rgb = DARK_SOFT
band.line.fill.background()

circle = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(9.72), Inches(1.55), Inches(2.95), Inches(2.95))
circle.fill.solid()
circle.fill.fore_color.rgb = DARK
circle.line.color.rgb = GOLD
circle.line.width = Pt(2)
textbox(s, 9.72, 2.35, 2.95, 0.9, "BA", 56, GOLD_LIGHT, True, font=FONT_TITLE, align=PP_ALIGN.CENTER)

textbox(s, 0.8, 0.55, 7.8, 0.3, "TPI BASES DE DATOS · UTN SAN RAFAEL", 10.5, GOLD_LIGHT, True)
textbox(s, 0.8, 1.35, 7.7, 2.0, "La base de datos\ncomo motor de reglas", 40, WHITE, True, font=FONT_TITLE, line_spacing=0.95)
textbox(s, 0.8, 3.5, 7.7, 0.5, "Bodegas del Atuel", 24, GOLD_LIGHT, True, font=FONT_TITLE)
textbox(s, 0.8, 4.08, 7.7, 0.7, "Modelo, integridad y rendimiento en PostgreSQL", 15, WHITE, font=FONT_BODY)

line = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.8), Inches(5.18), Inches(1.5), Inches(0.04))
line.fill.solid()
line.fill.fore_color.rgb = GOLD
line.line.fill.background()

textbox(s, 0.8, 5.42, 7.7, 0.6, "Jamardo, Camila (10842)\nSirotiuk, Juliana (10939)", 12, WHITE, font=FONT_BODY, line_spacing=1.25)

notes(s, "Buenas. Somos Camila y Juliana. Vamos a mostrar cómo modelamos Bodegas del Atuel y cómo PostgreSQL hace cumplir las reglas. Cada concepto va acompañado de un fragmento real del repositorio y de la prueba que lo respalda.")

# ---------------------------------------------------------------------------
# 2. La idea en una frase
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "El recorrido", "La idea en una frase")

quote = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.75), Inches(1.55), Inches(6.05), Inches(2.45))
quote.fill.solid()
quote.fill.fore_color.rgb = WHITE
quote.line.color.rgb = LINE
quote.line.width = Pt(0.75)
try:
    quote.adjustments[0] = 0.06
except Exception:
    pass
textbox(s, 1.02, 1.66, 0.55, 0.6, "“", 44, GOLD, True, font=FONT_TITLE)
textbox(s, 1.05, 2.0, 5.45, 1.7, "La API no calcula nada:\npide operaciones.\nPostgreSQL valida, calcula y audita.", 23, DARK, True, font=FONT_TITLE, line_spacing=1.08)

textbox(s, 1.05, 5.12, 5.6, 0.4, "Teoría  →  código real  →  evidencia", 13, MUTED, True)

card(s, 7.15, 1.55, 5.4, 1.0, "01", "Modelo y normalización", "DER/MER, 1FN–3FN y jerarquía de clientes.", GOLD)
card(s, 7.15, 2.72, 5.4, 1.0, "02", "Integridad y reglas", "Constraints, triggers y procedimientos.", GREEN)
card(s, 7.15, 3.89, 5.4, 1.0, "03", "Operación y seguridad", "Vistas, roles y privilegio mínimo.", GOLD)
card(s, 7.15, 5.06, 5.4, 1.0, "04", "Rendimiento y demo", "Índices, planes y cuatro evidencias.", GREEN)

footer(s, 2, "La base como única fuente de verdad")
notes(s, "La presentación sigue el recorrido del dato: primero el modelo, después las reglas que lo protegen, luego las operaciones y el rendimiento. Cerramos con una demo de cuatro evidencias.")

# ---------------------------------------------------------------------------
# 3. Arquitectura
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Arquitectura", "Tres capas, una sola fuente de verdad")

boxes = [
    ("Navegador", "HTML · CSS · JS", "Presenta y envía\noperaciones"),
    ("Front · Nginx", "estático + proxy", "Sirve el panel y\nenruta /api"),
    ("API · FastAPI", "SQL parametrizado", "Valida formato y\ntraduce errores"),
    ("PostgreSQL 18", "reglas y datos", "Valida, calcula,\naudita y protege"),
]
x0 = 0.75
bw = 2.42
gap = 0.58
for i, (title, sub, desc) in enumerate(boxes):
    x = x0 + i * (bw + gap)
    rect = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(1.78), Inches(bw), Inches(1.55))
    rect.fill.solid()
    rect.fill.fore_color.rgb = WHITE if i < 3 else DARK
    rect.line.color.rgb = GOLD if i == 3 else LINE
    rect.line.width = Pt(1.25 if i == 3 else 0.75)
    try:
        rect.adjustments[0] = 0.07
        rect.shadow.inherit = False
    except Exception:
        pass
    textbox(s, x + 0.16, 1.92, bw - 0.32, 0.32, title, 15, WHITE if i == 3 else DARK, True)
    textbox(s, x + 0.16, 2.26, bw - 0.32, 0.26, sub, 9.5, GOLD_LIGHT if i == 3 else GOLD, True)
    textbox(s, x + 0.16, 2.62, bw - 0.32, 0.55, desc, 10.5, WHITE if i == 3 else MUTED, line_spacing=1.05)
    if i < 3:
        arrow = s.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW, Inches(x + bw + 0.12), Inches(2.36), Inches(0.34), Inches(0.32))
        arrow.fill.solid()
        arrow.fill.fore_color.rgb = GOLD
        arrow.line.fill.background()

bullets(s, 0.85, 3.85, 11.6, 1.8, [
    "**El front no decide:** muestra datos y envía operaciones.",
    "**La API no duplica reglas:** valida formato, arma SQL parametrizado y traduce SQLSTATE a HTTP.",
    "**La base no es un depósito:** hace cumplir las reglas aunque el cliente sea `psql`, un script o el front.",
], 15, BODY, 10)

callout = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.75), Inches(5.9), Inches(11.85), Inches(0.72))
callout.fill.solid()
callout.fill.fore_color.rgb = CREAM
callout.line.fill.background()
try:
    callout.adjustments[0] = 0.18
except Exception:
    pass
textbox(s, 1.0, 6.08, 11.3, 0.36, "La regla de negocio no se mudó a la API: sigue viviendo en PostgreSQL.", 14, DARK, True, font=FONT_TITLE)

footer(s, 3, "docker-compose.yml · api/app/repositories · db/migrations")
notes(s, "Tres capas. El navegador consume el front; el front llama a la API; la API habla con PostgreSQL. La regla no está en el front ni en la API: está en la base. La API no usa ORM: todo el SQL vive en api/app/repositories/.")

# ---------------------------------------------------------------------------
# 4. DER / MER
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Modelo", "Del DER al MER")

bullets(s, 0.8, 1.55, 4.45, 3.8, [
    "**Entidades principales:** cliente, vino, comprobante, stock, ingreso y transferencia.",
    "**1:N con FK:** un cliente tiene muchos comprobantes; una sala tiene muchas ventas.",
    "**N:M con tabla puente:** `composicion` y `vino_maridaje`.",
    "**Jerarquía de clientes:** tabla común + subtipos.",
], 13.5, BODY, 9)

textbox(s, 0.8, 5.42, 4.5, 0.3, "DER conceptual", 10, GOLD, True)
textbox(s, 0.8, 5.72, 4.5, 0.7, "docs/DER-Bodegas-del-Atuel.jpg\ndocs/MER-Bodegas-del-Atuel.jpg", 9.5, MUTED, font=FONT_CODE, line_spacing=1.2)

img_card = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(5.45), Inches(1.45), Inches(7.15), Inches(5.22))
img_card.fill.solid()
img_card.fill.fore_color.rgb = WHITE
img_card.line.color.rgb = LINE
img_card.line.width = Pt(0.75)
try:
    img_card.adjustments[0] = 0.03
    img_card.shadow.inherit = False
except Exception:
    pass

img_path = ROOT / "docs" / "DER-Bodegas-del-Atuel.jpg"
pic = s.shapes.add_picture(str(img_path), Inches(5.62), Inches(1.62), width=Inches(6.8))
# Ajuste de altura máximo
max_h = 4.85
if pic.height > Inches(max_h):
    ratio = Inches(max_h) / pic.height
    pic.height = Inches(max_h)
    pic.width = int(pic.width * ratio)
textbox(s, 5.65, 6.48, 6.8, 0.25, "DER · 30 tablas · relaciones y jerarquías", 9, MUTED, align=PP_ALIGN.RIGHT)

footer(s, 4, "db/migrations/001_esquema.sql · 002_constraints.sql")
notes(s, "El DER es el modelo conceptual; el MER es la traducción a tablas, claves y relaciones. Las N:M no se guardan como listas: se resuelven con tablas puente. La jerarquía de clientes evita repetir datos comunes en cada subtipo.")

# ---------------------------------------------------------------------------
# 5. Normalización
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Normalización", "1FN · 2FN · 3FN aplicadas")

card(s, 0.75, 1.5, 4.9, 1.12, "1FN", "Atributos atómicos", "Calle y número separados; documento y tipo de documento en columnas propias.", GOLD)
card(s, 0.75, 2.78, 4.9, 1.12, "2FN", "Dependencia de la clave completa", "En composicion, porcentaje depende de (codigo_vino, id_cepa), no de una parte.", GREEN)
card(s, 0.75, 4.06, 4.9, 1.12, "3FN", "Sin dependencias transitivas", "Cliente guarda lo común; cada subtipo agrega solo sus atributos.", GOLD)

code_box(s, 6.0, 1.62, 6.6, 3.83, """
CREATE TABLE cliente (
  id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tipo tipo_cliente NOT NULL,
  nombre VARCHAR(60),
  calle VARCHAR(60) NOT NULL,
  numero VARCHAR(10) NOT NULL,
  CONSTRAINT uk_cliente_id_tipo UNIQUE (id, tipo)
);

CREATE TABLE socio_club (
  id_cliente INT PRIMARY KEY,
  tipo tipo_cliente NOT NULL,
  FOREIGN KEY (id_cliente, tipo)
    REFERENCES cliente (id, tipo)
);

CREATE TABLE composicion (
  codigo_vino INT NOT NULL,
  id_cepa INT NOT NULL,
  porcentaje NUMERIC(5,2) NOT NULL,
  PRIMARY KEY (codigo_vino, id_cepa)
);
""", 9.6, "001_esquema.sql")

callout = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.75), Inches(5.55), Inches(11.85), Inches(0.95))
callout.fill.solid()
callout.fill.fore_color.rgb = CREAM
callout.line.fill.background()
try:
    callout.adjustments[0] = 0.14
except Exception:
    pass
textbox(s, 1.0, 5.72, 11.3, 0.6, "El subtipo no repite nombre, documento ni domicilio: la tabla común guarda lo compartido y cada subtipo solo lo propio.", 13, DARK, True, font=FONT_TITLE, line_spacing=1.05)

footer(s, 5, "db/migrations/001_esquema.sql · cliente, socio_club, composicion")
notes(s, "1FN: atributos atómicos; la dirección se separa en calle y número. 2FN: en composicion, el porcentaje depende de la clave completa (vino, cepa). 3FN: cliente guarda lo común y los subtipos solo lo propio; no hay dependencias transitivas.")

# ---------------------------------------------------------------------------
# 6. Integridad declarativa
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Integridad", "Las reglas viven en el esquema")

code_box(s, 0.75, 1.62, 7.25, 3.05, """
ALTER TABLE vino
  ADD CONSTRAINT ck_vino_precio_positivo
      CHECK (precio > 0),
  ADD CONSTRAINT uk_vino_nombre_añada_volumen
      UNIQUE (nombre, añada, volumen_ml);

ALTER TABLE renglon_comprobante
  ADD CONSTRAINT ck_renglon_comprobante_cantidad_positiva
      CHECK (cantidad > 0);

ALTER TABLE stock_sala
  ADD CONSTRAINT ck_stock_sala_cantidad_no_negativa
      CHECK (cantidad >= 0);
""", 12.5, "002_constraints.sql")

bullets(s, 8.3, 1.62, 4.25, 3.5, [
    "**CHECK:** precio > 0, cantidades > 0 y stock >= 0.",
    "**UNIQUE:** no se repite nombre + añada + volumen.",
    "**FOREIGN KEY:** no hay comprobantes sin cliente ni vinos sin bodega.",
    "**La API puede validar antes, pero la base es la última palabra.**",
], 13.2, BODY, 8)

for i, (label, x) in enumerate([("RN-01", 0.8), ("RN-09", 2.15), ("RN-15", 3.5)]):
    chip(s, x, 4.95, 1.15, label, GREEN)
textbox(s, 4.95, 5.01, 7.6, 0.3, "Probados en tests/db_tests.sql · 133 verificaciones OK", 11.5, MUTED, font=FONT_BODY)

footer(s, 6, "db/migrations/002_constraints.sql · tests/db_tests.sql")
notes(s, "Los constraints son la última línea de defensa. Aunque la API o el front validen, la base rechaza precio negativo, vinos duplicados y stock negativo. Cualquier cliente que se conecte, incluso psql, cumple las mismas reglas.")

# ---------------------------------------------------------------------------
# 7. Triggers
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Triggers", "La venta se calcula sola")

bullets(s, 0.8, 1.55, 4.3, 4.2, [
    "**BEFORE valida; AFTER actualiza.**",
    "**AFTER INSERT** sobre cada renglón.",
    "**Misma transacción:** stock y totales.",
    "**Sin stock suficiente:** excepción y rollback.",
    "**La API no envía totales:** solo cabecera y renglón.",
], 13.5, BODY, 8)

code_box(s, 5.35, 1.62, 7.25, 3.35, """
CREATE TRIGGER trg_renglon_comprobante_actualiza_venta
AFTER INSERT ON renglon_comprobante
FOR EACH ROW
EXECUTE FUNCTION trg_actualizar_stock_y_totales_venta();

-- dentro de la función
UPDATE stock_sala
   SET cantidad = cantidad - NEW.cantidad
 WHERE id_sala = v_id_sala
   AND codigo_vino = NEW.codigo_vino;

UPDATE comprobante
   SET subtotal = v_subtotal,
       descuento_total = v_descuento_total,
       total = v_total
 WHERE numero = NEW.numero_comprobante;
""", 11, "005_triggers.sql")

callout = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.75), Inches(5.25), Inches(11.85), Inches(0.5))
callout.fill.solid()
callout.fill.fore_color.rgb = CREAM
callout.line.fill.background()
textbox(s, 1.0, 5.35, 11.2, 0.3, "Evidencia: RN-08 calcula totales · RN-09 rechaza la sobreventa y deja el stock intacto.", 12, DARK, True)

footer(s, 7, "db/migrations/005_triggers.sql · líneas 72–152")
notes(s, "La API inserta la cabecera y el renglón, pero no manda totales. El trigger descuenta stock y recalcula subtotal, descuento y total en la misma transacción. Si el stock no alcanza, lanza una excepción y se revierte todo: no queda un comprobante a medias.")

# ---------------------------------------------------------------------------
# 8. Procedimientos
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Procedimientos", "Una sola puerta de entrada")

code_box(s, 0.75, 1.62, 7.55, 3.55, """
CREATE PROCEDURE p_procesar_ingreso(p_codigo INT)
...
SELECT estado FROM ingreso
 WHERE codigo = p_codigo
 FOR UPDATE;

IF v_estado <> 'terminado' THEN
  RAISE EXCEPTION 'El ingreso % no esta terminado';
END IF;

INSERT INTO stock_deposito (codigo_vino, cantidad)
SELECT codigo_vino, cantidad
  FROM renglon_ingreso
 WHERE codigo_ingreso = p_codigo
ON CONFLICT (codigo_vino) DO UPDATE
  SET cantidad = stock_deposito.cantidad
               + EXCLUDED.cantidad;
""", 11, "004_procedimientos.sql")
bullets(s, 8.6, 1.55, 4.0, 4.5, [
    "**FOR UPDATE:** bloquea la cabecera.",
    "**Valida estado:** solo ingreso terminado.",
    "**Exige renglones:** no procesa un documento vacío.",
    "**Suma stock con ON CONFLICT.**",
    "**Estado final:** procesado.",
], 12.8, BODY, 8)

callout = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.75), Inches(5.45), Inches(11.85), Inches(0.5))
callout.fill.solid()
callout.fill.fore_color.rgb = CREAM
callout.line.fill.background()
textbox(s, 1.0, 5.55, 11.2, 0.3, "La API solo hace CALL. Evidencia: RN-10 (ingreso) y RN-11 (transferencia).", 12, DARK, True)

footer(s, 8, "db/migrations/004_procedimientos.sql · p_procesar_ingreso / p_procesar_transferencia")
notes(s, "El procedimiento bloquea la cabecera con FOR UPDATE, valida el estado, verifica que haya renglones y actualiza el depósito. La API solo hace CALL. Así dos sesiones no procesan el mismo ingreso y el stock no se suma dos veces.")

# ---------------------------------------------------------------------------
# 9. Vistas
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Vistas", "Una definición, muchos consumidores")

code_box(s, 0.75, 1.62, 7.55, 3.2, """
CREATE VIEW vista_stock_total_por_vino AS
SELECT v.codigo, v.nombre,
       COALESCE(d.cantidad, 0) AS stock_deposito,
       COALESCE(s.cantidad, 0) AS stock_sala,
       COALESCE(d.cantidad, 0)
       + COALESCE(s.cantidad, 0) AS stock_total
FROM vino v
LEFT JOIN stock_deposito d
       ON d.codigo_vino = v.codigo
LEFT JOIN (
    SELECT codigo_vino, SUM(cantidad) AS cantidad
    FROM stock_sala
    GROUP BY codigo_vino
) s ON s.codigo_vino = v.codigo;
""", 11.5, "006_vistas.sql")

bullets(s, 8.6, 1.55, 4.0, 4.4, [
    "**Oculta joins y agregaciones.**",
    "**Métrica consistente:** depósito + salas.",
    "**LEFT JOIN:** un vino sin stock sigue apareciendo.",
    "**La usan la ficha del vino y los reportes.**",
], 13, BODY, 9)

callout = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.75), Inches(5.05), Inches(11.85), Inches(0.5))
callout.fill.solid()
callout.fill.fore_color.rgb = CREAM
callout.line.fill.background()
textbox(s, 1.0, 5.15, 11.2, 0.3, "No es una tabla: se recalcula con los datos actuales y evita duplicar la lógica en cada consulta.", 12, DARK, True)

footer(s, 9, "db/migrations/006_vistas.sql · vista_stock_total_por_vino")
notes(s, "La vista encapsula el join y la suma de stock. El consumidor pide stock_total y no repite la lógica. El LEFT JOIN es importante: un vino sin stock en depósito o en salas sigue apareciendo con cero. La usan la ficha del vino y los reportes.")

# ---------------------------------------------------------------------------
# 10. Roles
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Seguridad", "Privilegio mínimo, secretos fuera del repo")

code_box(s, 0.75, 1.62, 7.15, 3.7, """
CREATE ROLE rol_api LOGIN;
CREATE ROLE rol_reporte LOGIN;

-- 4. rol_api: lectura y escritura
GRANT SELECT, INSERT, UPDATE, DELETE ON
    bodega, vino, comprobante, stock_sala, ...
TO rol_api;

GRANT SELECT, INSERT ON auditoria_precio TO rol_api;
GRANT EXECUTE ON ALL PROCEDURES
    IN SCHEMA public TO rol_api;

GRANT SELECT ON
    vista_stock_total_por_vino,
    vista_ventas_mensuales_por_sala,
    vista_documentos_pendientes
TO rol_reporte;
""", 11.2, "007_roles.sql")

card(s, 8.2, 1.55, 4.35, 1.25, "API", "rol_api", "DML sobre tablas operativas, auditoría de solo lectura y execute de procedimientos.", GOLD)
card(s, 8.2, 2.95, 4.35, 1.25, "REP", "rol_reporte", "Solo SELECT sobre las tres vistas de reportes.", GREEN)
card(s, 8.2, 4.35, 4.35, 1.25, "KEY", "Claves por entorno", "99_password_api.sql toma APP_DB_PASSWORD y APP_REPORT_PASSWORD. No hay literales.", GOLD)

callout = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.75), Inches(5.65), Inches(11.85), Inches(0.5))
callout.fill.solid()
callout.fill.fore_color.rgb = CREAM
callout.line.fill.background()
textbox(s, 1.0, 5.75, 11.2, 0.3, "La API nunca se conecta como owner. /salud devuelve current_user = rol_api.", 12, DARK, True)

footer(s, 10, "db/migrations/007_roles.sql · db/initdb/99_password_api.sql")
notes(s, "La API se conecta como rol_api, nunca como propietario ni superusuario. rol_reporte solo lee vistas. Las claves se fijan por entorno en db/initdb/99_password_api.sql: no hay credenciales literales en el repositorio.")

# ---------------------------------------------------------------------------
# 11. Índices
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Rendimiento", "Índices: menos buffers, no más código")

table(s, 0.75, 1.55, 5.25, 2.35, [
    ["Consulta", "Antes", "Después", "Mejora"],
    ["S3", "9,753 ms", "0,977 ms", "10,0×"],
    ["S8", "15,490 ms", "9,174 ms", "1,69×"],
    ["S9", "77 buf", "3 buf", "25,7×"],
], [1.25, 1.25, 1.3, 1.1], 11.5)
textbox(s, 0.78, 4.02, 5.2, 0.55, "Mediana de 3 corridas con EXPLAIN (ANALYZE, BUFFERS).", 10.5, MUTED, italic=True)

code_box(s, 6.25, 1.62, 6.35, 1.8, """
CREATE INDEX idx_comprobante_sala_fecha
  ON comprobante (id_sala_venta, fecha)
  INCLUDE (id_cliente);

CREATE INDEX idx_comprobante_fecha_sala_total
  ON comprobante (fecha, id_sala_venta)
  INCLUDE (total);
""", 11.5, "008_indices.sql")

callout = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.75), Inches(4.85), Inches(11.85), Inches(0.95))
callout.fill.solid()
callout.fill.fore_color.rgb = CREAM
callout.line.fill.background()
textbox(s, 1.0, 5.02, 11.3, 0.7, "No todos los índices ayudan: S1, S11 y S12 siguen con Seq Scan porque leen casi toda la tabla. El índice se justifica con el plan, no con la intuición.", 12.5, DARK, True, font=FONT_TITLE, line_spacing=1.08)

footer(s, 11, "docs/informe_etapa4_indices.md · planes antes/después")
notes(s, "El orden de columnas importa: primero la igualdad o el rango, después el resto. INCLUDE permite un Index Only Scan sin visitar el heap. No todos los índices ayudan: S1, S11 y S12 siguen con Seq Scan porque leen casi toda la tabla. Eso también se documentó.")

# ---------------------------------------------------------------------------
# 12. Demo
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, BG)
header(s, "Demo en vivo", "Cuatro evidencias en 4 minutos")

steps = [
    ("1", "Venta exitosa", "Totales y stock calculados por la base."),
    ("2", "Venta sin stock", "HTTP 409, stock intacto, sin comprobante."),
    ("3", "Transferencia", "Crear, terminar y procesar."),
    ("4", "Plan de ejecución", "EXPLAIN ANALYZE: Index Only Scan."),
]
for i, (num, title, desc) in enumerate(steps):
    y = 1.55 + i * 1.12
    circle = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(0.85), Inches(y), Inches(0.48), Inches(0.48))
    circle.fill.solid()
    circle.fill.fore_color.rgb = DARK if i % 2 == 0 else GREEN
    circle.line.fill.background()
    textbox(s, 0.85, y + 0.09, 0.48, 0.3, num, 13, WHITE, True, align=PP_ALIGN.CENTER)
    textbox(s, 1.55, y - 0.02, 2.2, 0.32, title, 14, DARK, True)
    textbox(s, 3.75, y - 0.02, 4.2, 0.5, desc, 11.5, MUTED)

box = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(8.35), Inches(1.55), Inches(4.2), Inches(3.85))
box.fill.solid()
box.fill.fore_color.rgb = WHITE
box.line.color.rgb = LINE
box.line.width = Pt(0.75)
try:
    box.adjustments[0] = 0.05
except Exception:
    pass
textbox(s, 8.6, 1.72, 3.7, 0.3, "QUÉ MIRAR", 9.5, GOLD, True)
bullets(s, 8.6, 2.08, 3.65, 2.5, [
    "HTTP **409** y mensaje de la base.",
    "Stock **antes = después**.",
    "**Index Only Scan** y buffers.",
    "30 tablas y 796.681 filas.",
    "**SQLSTATE** traducido a HTTP.",
], 11.5, BODY, 7, GREEN)

divider = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(8.6), Inches(4.62), Inches(3.65), Inches(0.012))
divider.fill.solid()
divider.fill.fore_color.rgb = LINE
divider.line.fill.background()
textbox(s, 8.6, 4.74, 3.65, 0.45, "Si la red falla: capturas de respaldo.", 10, MUTED, italic=True, line_spacing=1.1)

textbox(s, 0.85, 6.15, 11.6, 0.3, "Front  http://localhost:8080     ·     API  http://localhost:8000/docs     ·     Salud  /api/salud", 10.5, MUTED, font=FONT_CODE)

footer(s, 12, "Si el 8080 está ocupado, el front se publica en 8081 con FRONT_PORT.")
notes(s, "La demo sigue el mismo orden que la presentación. Si la red o la nube fallan, usar las capturas de respaldo. Mostrar siempre el antes y el después del stock, y el plan de ejecución.")

# ---------------------------------------------------------------------------
# 13. Cierre
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, DARK)

line = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.85), Inches(1.05), Inches(1.4), Inches(0.05))
line.fill.solid()
line.fill.fore_color.rgb = GOLD
line.line.fill.background()

textbox(s, 0.85, 1.45, 7.3, 1.0, "Lo que demuestra el TPI", 36, WHITE, True, font=FONT_TITLE)
bullets(s, 0.9, 3.05, 7.2, 2.2, [
    "Modelo normalizado y trazable.",
    "Reglas ejecutadas por la base, no por la aplicación.",
    "Rendimiento medido, no supuesto.",
], 17, WHITE, 14, GOLD_LIGHT)

textbox(s, 0.9, 5.9, 7.2, 0.8, "Jamardo, Camila · 10842\nSirotiuk, Juliana · 10939", 10.5, GOLD_LIGHT, line_spacing=1.3)

rule = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(9.55), Inches(1.15), Inches(0.045), Inches(4.95))
rule.fill.solid()
rule.fill.fore_color.rgb = GOLD
rule.line.fill.background()

gracias = textbox(
    s, 8.35, 3.05, 4.6, 1.35, "Gracias", 64, GOLD_LIGHT, True,
    font=FONT_TITLE, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE,
)
gracias.rotation = 270

notes(s, "Cierre: el TPI demuestra que la base no es un depósito de datos, es el motor de reglas del sistema. Quedamos disponibles para cualquier consulta sobre el trabajo.")

# ---------------------------------------------------------------------------
# Guardar
# ---------------------------------------------------------------------------
OUT.parent.mkdir(parents=True, exist_ok=True)
prs.save(OUT)
print(f"Presentación generada: {OUT}")
print(f"Slides: {len(prs.slides)}")
