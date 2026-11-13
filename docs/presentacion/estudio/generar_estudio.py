#!/usr/bin/env python3
"""Genera la guía de estudio de la defensa (Bodegas del Atuel)."""

from __future__ import annotations

import os
import re
from pathlib import Path

from PIL import ImageFont
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "Bodegas_del_Atuel_Guia_Estudio.pptx"

BG = RGBColor(0xF6, 0xF1, 0xE7)
WHITE = RGBColor(0xFF, 0xFD, 0xF9)
CREAM = RGBColor(0xEF, 0xE7, 0xD9)
DARK = RGBColor(0x4A, 0x10, 0x20)
DARK_SOFT = RGBColor(0x63, 0x1B, 0x2C)
GOLD = RGBColor(0xB0, 0x7A, 0x3A)
GOLD_LIGHT = RGBColor(0xD9, 0xB5, 0x7A)
GREEN = RGBColor(0x2E, 0x6B, 0x4F)
BODY = RGBColor(0x3A, 0x33, 0x2C)
MUTED = RGBColor(0x6F, 0x64, 0x58)
LINE = RGBColor(0xD9, 0xCF, 0xBE)

FONT_TITLE = "Cambria"
FONT_BODY = "Segoe UI"
FONT_CODE = "Consolas"

W = 13.333
H = 7.5

# Región de contenido y banda fija de cierre (el "takeaway" de cada slide).
TOP = 1.55
BOTTOM = 5.95
BAND_Y = 6.14


# ---------------------------------------------------------------------------
# Medición de texto (para que las cajas se ajusten al contenido)
# ---------------------------------------------------------------------------
FONT_FILES = {
    ("Segoe UI", False): "segoeui.ttf",
    ("Segoe UI", True): "segoeuib.ttf",
    ("Consolas", False): "consola.ttf",
    ("Cambria", False): "cambria.ttf",
    ("Cambria", True): "cambriab.ttf",
}
_FONT_CACHE: dict = {}


def _font(font: str, bold: bool, size: float):
    key = (font, bold, size)
    if key not in _FONT_CACHE:
        path = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts", FONT_FILES[(font, bold)])
        _FONT_CACHE[key] = ImageFont.truetype(path, max(6, int(round(size * 4))))
    return _FONT_CACHE[key]


def run_width(text: str, size: float, font: str = FONT_BODY, bold: bool = False) -> float:
    try:
        return _font(font, bold, size).getlength(text) / 4 / 72.0
    except Exception:
        return len(text) * 0.5 * size / 72.0


def _tokens(text: str):
    """Divide el texto en (palabra, fuente, negrita) interpretando ** y `."""
    out = []
    for part in re.split(r"(\*\*.*?\*\*|`.*?`)", text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            out.append((part[2:-2], FONT_BODY, True))
        elif part.startswith("`") and part.endswith("`"):
            out.append((part[1:-1], FONT_CODE, False))
        else:
            out.append((part, FONT_BODY, False))
    return out


def text_lines(text: str, width_in: float, size: float, bold: bool = False, font: str = FONT_BODY) -> int:
    words = []
    for chunk, chunk_font, chunk_bold in _tokens(text):
        for piece in chunk.split(" "):
            if piece:
                words.append((piece, chunk_font, chunk_bold or bold))
    if not words:
        return 1
    space_w = run_width(" ", size, font)
    lines, cur = 1, 0.0
    for word, word_font, word_bold in words:
        w = run_width(word, size, word_font, word_bold)
        add = w + (space_w if cur > 0 else 0.0)
        if cur == 0 or cur + add <= width_in:
            cur += add
        else:
            lines += 1
            cur = w
    return lines


def line_h(size: float, spacing: float = 1.0) -> float:
    return size * 1.2 * spacing / 72.0


def bullets_height(items, width_in, size, space) -> float:
    total = 0.0
    for item in items:
        text = item[2:] if item.startswith("# ") else item
        total += text_lines("•  " + text, width_in, size) * line_h(size, 1.04) + 0.035
    return total + (len(items) - 1) * space / 72.0


# ---------------------------------------------------------------------------
# Primitivas de dibujo
# ---------------------------------------------------------------------------
def set_bg(slide, color: RGBColor) -> None:
    fill = slide.background.fill
    fill.solid()
    fill.fore_color.rgb = color


def textbox(
    slide, x, y, w, h, text="", size=16, color=BODY, bold=False, italic=False,
    font=FONT_BODY, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP,
    line_spacing=1.0, margins=(0, 0, 0, 0),
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


def add_rich_runs(p, text: str, size: float, color: RGBColor, font: str = FONT_BODY) -> None:
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


def rich_box(slide, x, y, w, h, text, size, color=MUTED, line_spacing=1.06):
    box = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    for index, line in enumerate(text.split("\n")):
        p = tf.paragraphs[0] if index == 0 else tf.add_paragraph()
        p.line_spacing = line_spacing
        add_rich_runs(p, line, size, color)
    return box


def bullets(slide, x, y, w, items, size=12.5, color=BODY, space=7, bullet_color=GOLD):
    box = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(0.4))
    tf = box.text_frame
    tf.word_wrap = True
    tf.margin_left = 0
    tf.margin_right = 0
    tf.margin_top = 0
    tf.margin_bottom = 0
    for index, item in enumerate(items):
        p = tf.paragraphs[0] if index == 0 else tf.add_paragraph()
        p.line_spacing = 1.04
        p.space_after = Pt(space)
        pPr = p._p.get_or_add_pPr()
        pPr.set("marL", "177800")
        pPr.set("indent", "-177800")
        text = item[2:] if item.startswith("# ") else item
        r = p.add_run()
        marker = re.match(r"^(\d+)\. ", text)
        if marker:
            r.text = f"{marker.group(1)}.  "
            text = text[marker.end():]
        else:
            r.text = "•  "
        r.font.name = FONT_BODY
        r.font.size = Pt(size)
        r.font.color.rgb = bullet_color
        add_rich_runs(p, text, size, color)
    return box


def header(slide, kicker: str, title: str) -> None:
    a = textbox(slide, 0.75, 0.34, 9.0, 0.28, kicker.upper(), 10, GOLD, True)
    b = textbox(slide, 0.75, 0.6, 11.9, 0.62, title, 28, DARK, True, font=FONT_TITLE)
    line = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.75), Inches(1.26), Inches(1.15), Inches(0.045))
    line.fill.solid()
    line.fill.fore_color.rgb = GOLD
    line.line.fill.background()
    for shape in (a, b, line):
        shape.name = "hdr"


def footer(slide, number: int, source: str | None = None) -> None:
    line = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.75), Inches(7.04), Inches(11.85), Inches(0.012))
    line.fill.solid()
    line.fill.fore_color.rgb = LINE
    line.line.fill.background()
    line.name = "ftr"
    if source:
        s1 = textbox(slide, 0.75, 7.1, 8.6, 0.24, source, 8.5, MUTED)
        s1.name = "ftr"
    s2 = textbox(slide, 9.5, 7.1, 3.1, 0.24, f"Guía de estudio · {number:02d}", 8.5, MUTED, align=PP_ALIGN.RIGHT)
    s2.name = "ftr"


def callout(slide, text, y=BAND_Y, size=13.0, accent=GOLD):
    w, inner = 11.85, 11.25
    lines = text_lines(text, inner, size, bold=True, font=FONT_TITLE)
    h = max(0.5, lines * line_h(size, 1.06) + 0.26)
    rect = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.75), Inches(y), Inches(w), Inches(h))
    rect.fill.solid()
    rect.fill.fore_color.rgb = CREAM
    rect.line.fill.background()
    rect.name = "co"
    try:
        rect.adjustments[0] = 0.16
    except Exception:
        pass
    bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.75), Inches(y + 0.08), Inches(0.055), Inches(h - 0.16))
    bar.fill.solid()
    bar.fill.fore_color.rgb = accent
    bar.line.fill.background()
    bar.name = "co"
    txt = textbox(slide, 1.05, y + 0.1, inner, h - 0.16, text, size, DARK, True, font=FONT_TITLE, line_spacing=1.06)
    txt.name = "co"
    return y + h


def callout_height(text, size=13.0) -> float:
    return max(0.5, text_lines(text, 11.25, size, bold=True, font=FONT_TITLE) * line_h(size, 1.06) + 0.26)


def fit(content_h, callout_text, size=13.0, top=TOP, bottom=6.86, gap=0.42):
    """Centra el bloque contenido + banda de cierre en la diapositiva."""
    group = content_h + gap + callout_height(callout_text, size)
    y = top + max(0.0, (bottom - top - group) / 2.0)
    return y, y + content_h + gap


# ---------------------------------------------------------------------------
# Paneles y tarjetas de altura automática
# ---------------------------------------------------------------------------
def panel_height(items, w, size=12.8, space=9) -> float:
    return 0.52 + bullets_height(items, w - 0.55, size, space) + 0.20


def draw_panel(slide, x, y, w, h, title, items, accent=GOLD, size=12.8, space=9):
    rect = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    rect.fill.solid()
    rect.fill.fore_color.rgb = WHITE
    rect.line.color.rgb = LINE
    rect.line.width = Pt(0.75)
    try:
        rect.adjustments[0] = 0.045
        rect.shadow.inherit = False
    except Exception:
        pass
    textbox(slide, x + 0.28, y + 0.16, w - 0.55, 0.24, title.upper(), 9.5, accent, True)
    bullets(slide, x + 0.28, y + 0.52, w - 0.55, items, size, BODY, space)


def panels_row(slide, y, specs, x=0.75, total_w=11.85, gap=0.16, size=12.8, space=9, h=None):
    n = len(specs)
    w = (total_w - gap * (n - 1)) / n
    if h is None:
        h = max(panel_height(s["items"], w, s.get("size", size), s.get("space", space)) for s in specs)
    for i, spec in enumerate(specs):
        draw_panel(
            slide, x + i * (w + gap), y, w, h,
            spec["title"], spec["items"], spec.get("accent", GOLD),
            spec.get("size", size), spec.get("space", space),
        )
    return y + h


def card_height(title, desc, w, size=12.0, title_size=14.0) -> float:
    tl = text_lines(title, w - 0.6, title_size, bold=True, font=FONT_BODY)
    dl = sum(text_lines(line, w - 0.55, size) for line in desc.split("\n"))
    return 0.20 + tl * line_h(title_size, 1.02) + 0.10 + dl * line_h(size, 1.06) + 0.24


def draw_card(slide, x, y, w, h, title, desc, accent=GOLD, size=12.0):
    rect = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    rect.fill.solid()
    rect.fill.fore_color.rgb = WHITE
    rect.line.color.rgb = LINE
    rect.line.width = Pt(0.75)
    try:
        rect.adjustments[0] = 0.06
        rect.shadow.inherit = False
    except Exception:
        pass
    tl = text_lines(title, w - 0.6, 13.5, bold=True)
    th = tl * line_h(13.5, 1.02)
    bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x + 0.22), Inches(y + 0.22), Inches(0.05), Inches(max(0.3, th - 0.04)))
    bar.fill.solid()
    bar.fill.fore_color.rgb = accent
    bar.line.fill.background()
    textbox(slide, x + 0.38, y + 0.2, w - 0.58, th + 0.05, title, 13.5, DARK, True, line_spacing=1.02)
    rich_box(slide, x + 0.25, y + 0.2 + th + 0.10, w - 0.5, h - (0.2 + th + 0.1), desc, size, MUTED)


def cards_row(slide, y, specs, x=0.75, total_w=11.85, gap=0.16, size=12.0, h=None, min_h=0.0):
    n = len(specs)
    w = (total_w - gap * (n - 1)) / n
    if h is None:
        h = max(max(card_height(s["title"], s["desc"], w, s.get("size", size)) for s in specs), min_h)
    for i, spec in enumerate(specs):
        draw_card(slide, x + i * (w + gap), y, w, h, spec["title"], spec["desc"], spec.get("accent", GOLD), spec.get("size", size))
    return y + h


def table(slide, x, y, w, h, data, widths, size=10.5, first_bold=True):
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
            cell.margin_left = Inches(0.1)
            cell.margin_right = Inches(0.1)
            cell.margin_top = Inches(0.03)
            cell.margin_bottom = Inches(0.03)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            tf = cell.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            p.alignment = PP_ALIGN.LEFT
            run = p.add_run()
            run.text = str(data[r][c])
            run.font.name = FONT_BODY
            run.font.size = Pt(size)
            run.font.bold = (r == 0) or (c == 0 and first_bold)
            run.font.color.rgb = WHITE if r == 0 else BODY


def qa_height(pairs, w, qsize=12.4, asize=10.7, gap=0.30) -> float:
    total = 0.0
    for q, a in pairs:
        total += text_lines(q, w - 0.2, qsize, bold=True) * line_h(qsize, 1.0)
        total += text_lines(a, w - 0.2, asize) * line_h(asize, 1.02)
        total += 0.06 + gap
    return total - gap


def qa_list(slide, x, y, w, pairs, qsize=12.4, asize=10.7, gap=0.30):
    cur = y
    for q, a in pairs:
        ql = text_lines(q, w - 0.2, qsize, bold=True)
        al = text_lines(a, w - 0.2, asize)
        qh = ql * line_h(qsize, 1.0)
        ah = al * line_h(asize, 1.02)
        bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(x), Inches(cur + 0.04), Inches(0.045), Inches(qh + ah + 0.02))
        bar.fill.solid()
        bar.fill.fore_color.rgb = GOLD
        bar.line.fill.background()
        textbox(slide, x + 0.2, cur - 0.02, w - 0.2, qh + 0.04, q, qsize, DARK, True, line_spacing=1.0)
        textbox(slide, x + 0.2, cur + qh + 0.05, w - 0.2, ah + 0.05, a, asize, MUTED, line_spacing=1.02)
        cur += qh + ah + 0.06 + gap
    return cur


def centered(content_h, top=TOP, bottom=BOTTOM, bias=0.45) -> float:
    return top + max(0.0, (bottom - top - content_h) * bias)


def notes(slide, text: str) -> None:
    slide.notes_slide.notes_text_frame.text = text


prs = Presentation()
prs.slide_width = Inches(W)
prs.slide_height = Inches(H)
blank = prs.slide_layouts[6]


def base(kicker, title):
    s = prs.slides.add_slide(blank)
    set_bg(s, BG)
    header(s, kicker, title)
    return s


# ---------------------------------------------------------------------------
# 1. Portada
# ---------------------------------------------------------------------------
s = prs.slides.add_slide(blank)
set_bg(s, DARK)
band = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(9.3), Inches(0), Inches(4.03), Inches(7.5))
band.fill.solid()
band.fill.fore_color.rgb = DARK_SOFT
band.line.fill.background()

textbox(s, 0.85, 0.7, 8.0, 0.3, "GUÍA DE ESTUDIO · TPI BASES DE DATOS", 10.5, GOLD_LIGHT, True)
textbox(s, 0.85, 1.5, 7.8, 1.6, "Cómo defender\nel modelo", 46, WHITE, True, font=FONT_TITLE, line_spacing=0.95)
textbox(s, 0.85, 3.35, 7.8, 0.45, "Bodegas del Atuel", 24, GOLD_LIGHT, True, font=FONT_TITLE)
textbox(s, 0.85, 3.95, 7.6, 0.7, "Teoría, decisiones y preguntas probables\npara el oral", 15, WHITE, line_spacing=1.2)

line = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.85), Inches(5.05), Inches(1.5), Inches(0.04))
line.fill.solid()
line.fill.fore_color.rgb = GOLD
line.line.fill.background()

textbox(s, 0.85, 5.25, 7.6, 0.35, "Material de estudio · 22 slides", 12.5, GOLD_LIGHT, True)
textbox(s, 0.85, 5.7, 7.6, 0.8, "Jamardo, Camila (10842) · Sirotiuk, Juliana (10939)", 11.5, WHITE, line_spacing=1.3)

textbox(s, 9.8, 2.45, 2.9, 1.0, "BA", 64, GOLD_LIGHT, True, font=FONT_TITLE, align=PP_ALIGN.CENTER)
circle = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(9.85), Inches(2.2), Inches(2.9), Inches(2.9))
circle.fill.background()
circle.line.color.rgb = GOLD
circle.line.width = Pt(1.75)

notes(s, "Esta guía complementa la presentación de defensa: no se proyecta, se estudia. La idea es que cada integrante pueda explicar el modelo con sus palabras, ubicar la decisión en el archivo y justificar por qué está ahí.")

# ---------------------------------------------------------------------------
# 2. Qué se evalúa
# ---------------------------------------------------------------------------
s = base("El oral", "Qué se evalúa (y cómo ordenar la respuesta)")
left = [
    "Cómo identificaron las entidades y qué las identifica.",
    "Por qué algo es tabla propia y no una columna de otra.",
    "Relaciones y cardinalidades: 1:N, N:M, tabla intermedia.",
    "Cómo llegaron a 1FN–2FN–3FN y qué redundancia conservaron.",
    "Qué decisiones tomaron y qué alternativas descartaron.",
    "Qué regla vive en clave, constraint, trigger o procedimiento.",
]
right = [
    "**¿Qué entidades?** → 001, DER y MER.",
    "**¿Cómo se relacionan?** → cardinalidades y tablas puente.",
    "**¿Por qué está normalizado?** → dependencias y formas normales.",
    "**¿Dónde vive cada regla?** → 002 a 005.",
    "**¿Qué descartaron?** → la decisión también se defiende.",
]
text = "Un error que entienden y saben explicar vale más que un modelo perfecto que no pueden justificar."
h = max(panel_height(left, 5.82), panel_height(right, 5.82))
y, cy = fit(h, text, size=12.6, bottom=6.25)
panels_row(s, y, [
    {"title": "Lo que miran", "items": left, "accent": GOLD},
    {"title": "Cuatro preguntas que ordenan todo", "items": right, "accent": GREEN},
], h=h)
callout(s, text, cy, 12.6)
footer(s, 2, "Criterios de la cátedra · defensa oral")
notes(s, "La cátedra no premia la perfección: premia el razonamiento. Cada respuesta debería nombrar la entidad o regla, el archivo donde vive y la alternativa que descartaron. Si no saben un detalle, conviene decir qué decisión lo explica.")

# ---------------------------------------------------------------------------
# 3. Claves
# ---------------------------------------------------------------------------
s = base("Teoría", "Claves: la identidad de cada fila")
table(s, 0.75, 1.5, 11.85, 4.35, [
    ["Concepto", "En Bodegas del Atuel"],
    ["Superclave", "Cualquier conjunto de columnas que identifica una fila."],
    ["Clave candidata", "Superclave minimal; puede haber más de una por tabla."],
    ["PK", "La candidata elegida. Subrogada (id, código, número) o natural (cuit, CP)."],
    ["UK", "Otra candidata. Ej.: documento activo del cliente; (id, tipo) en cliente."],
    ["FK", "Referencia a una PK o UK; garantiza integridad referencial."],
    ["Clave compuesta", "Renglones (documento, vino); parcela (finca, nro_parcela)."],
    ["Integridad referencial", "Toda FK apunta a una fila existente: la base rechaza huérfanos."],
], [2.55, 9.3], 11.5)
callout(s, "La UK (id, tipo) de cliente no es capricho: es el destino de la FK compuesta que hace disjunta la jerarquía.", 6.12, 12.4)
footer(s, 3, "001_esquema.sql · 002_constraints.sql")
notes(s, "Distinguir PK de UK es clave: la PK identifica; la UK también puede ser destino de una FK. En cliente, (id, tipo) existe para que la FK compuesta de cada subtipo valide el tipo. La PK compuesta aparece cuando la identidad depende del par, como en stock_sala o en los renglones.")

# ---------------------------------------------------------------------------
# 4. Dependencias y formas normales
# ---------------------------------------------------------------------------
s = base("Teoría", "Dependencias funcionales y formas normales")
left = [
    "**DF:** X → Y; el valor de X determina el de Y.",
    "**1FN:** atributos atómicos; lo multivaluado va a otra tabla.",
    "**2FN:** ningún atributo depende de parte de la clave.",
    "**3FN:** ningún atributo no clave depende de otro no clave.",
    "**BCNF:** toda DF parte de una clave candidata; acá no hizo falta.",
    "**Redundancia:** se permite si hay un mecanismo que la mantiene.",
]
right = [
    "`composicion`: (vino, cepa) → porcentaje.",
    "`renglon_comprobante`: (comprobante, vino) → cantidad, precio.",
    "`parcela`: (finca, número) → cepa, campaña.",
    "`cliente`: id → tipo → descuento; por eso el descuento se calcula.",
    "**Deliberadas:** `subtotal_renglon` (generada), totales (trigger + CHECK), campaña (generada).",
]
h = max(panel_height(left, 5.82), panel_height(right, 5.82))
y = centered(h, bottom=5.45)
panels_row(s, y, [
    {"title": "La teoría", "items": left, "accent": GOLD},
    {"title": "En el modelo", "items": right, "accent": GREEN},
], h=h)
callout(s, "Guardar un derivado se justifica solo si podés decir quién lo mantiene consistente.", 5.75, 12.6)
footer(s, 4, "003_funciones.sql · 005_triggers.sql · Justificación de diseño")
notes(s, "Si preguntan por 3FN, el ejemplo más fuerte es el descuento: id → tipo → descuento es transitiva, por eso no se guarda en cliente; se calcula con fn_descuento_cliente. Las redundancias que sí quedan (subtotal del renglón, totales del comprobante, campaña) tienen columna generada, trigger o CHECK que las sostiene.")

# ---------------------------------------------------------------------------
# 5. Cardinalidades
# ---------------------------------------------------------------------------
s = base("Teoría", "Cardinalidades y tablas puente")
specs = [
    {"title": "1:N", "accent": GOLD,
     "desc": "Cliente → comprobante. Sala → empleado. Bodega → vino. Finca → parcela.\nLa FK vive del lado N: muchos comprobantes, un cliente."},
    {"title": "N:M con atributos", "accent": GREEN,
     "desc": "Vino ↔ cepa: `composicion` guarda `porcentaje`.\nEl dato depende del par, no de una entidad sola."},
    {"title": "N:M sin atributos", "accent": GOLD,
     "desc": "Vino ↔ maridaje: `vino_maridaje` solo tiene las dos claves.\nTabla puente pura: la PK es el par."},
    {"title": "1:1 y 0:N", "accent": GREEN,
     "desc": "Vino ↔ `stock_deposito` (PK = vino). Renglones 0:N: la cabecera nace vacía y el trigger exige al menos uno."},
]
h = max(card_height(x["title"], x["desc"], 5.82, 11.6) for x in specs)
y = centered(2 * h + 0.18, bottom=5.55)
cards_row(s, y, specs[:2], h=h, size=11.6)
cards_row(s, y + h + 0.18, specs[2:], h=h, size=11.6)
callout(s, "Si el dato describe la relación y no a una entidad, su lugar es la tabla intermedia.", 5.85, 12.6)
footer(s, 5, "DER/MER · 001_esquema.sql")
notes(s, "La prueba para decidir si hace falta tabla intermedia: ¿la relación es N:M? ¿Tiene atributos propios? Si la respuesta es sí a cualquiera, va tabla. stock_sala y los renglones son N:M con atributos; vino_maridaje es N:M sin atributos. Cliente–sala no se modeló como N:M porque ya existe el comprobante que los vincula.")

# ---------------------------------------------------------------------------
# 6. 001 esquema
# ---------------------------------------------------------------------------
s = base("Migración 001", "Esquema: entidades, claves y límites")
left = [
    "30 tablas: 29 operativas + `auditoria_precio`.",
    "Subrogadas: id, código, número. Naturales: cuit, código postal.",
    "PK compuestas: renglones, composición, stock, parcela.",
    "Jerarquía de cliente y ENUM de estado y tipo.",
    "`comprobante` es la cabecera; `renglon_comprobante`, el detalle.",
    "Historial: el renglón guarda `precio_unitario`.",
]
right = [
    "`maridaje` es tabla: N:M y se comparte entre vinos.",
    "`departamento` es columna: no tiene clave ni relaciones.",
    "`email` y `teléfono` simples: un solo canal principal.",
    "`stock_deposito` es tabla 1:1: cantidad y PK propia.",
    "`stock_sala` es tabla: cantidad por sala y vino.",
]
h = max(panel_height(left, 5.82), panel_height(right, 5.82))
y = centered(h, bottom=5.55)
panels_row(s, y, [
    {"title": "Qué hay", "items": left, "accent": GOLD},
    {"title": "Tabla propia vs columna", "items": right, "accent": GREEN},
], h=h)
callout(s, "Una tabla propia existe cuando tiene clave, atributos y relaciones propias.", 5.85, 12.6)
footer(s, 6, "001_esquema.sql · 30 tablas")
notes(s, "La decisión tabla/columna se justifica por tres cosas: clave propia, atributos propios y relaciones. Maridaje cumple las tres; departamento no tiene clave ni se relaciona; email y teléfono se dejaron simples porque el negocio pide un canal principal. El renglón guarda precio_unitario para conservar el precio histórico aunque el vino cambie.")

# ---------------------------------------------------------------------------
# 7. 001 jerarquía
# ---------------------------------------------------------------------------
s = base("Migración 001", "Jerarquía de cliente y empleado")
left = [
    "`cliente`: id PK, `tipo` ENUM, UK (id, tipo).",
    "Subtipos: PK `id_cliente`, CHECK de `tipo`, FK (id_cliente, tipo).",
    "Un cliente no puede estar en dos subtipos: la PK lo impide.",
    "Total y disjunta; la totalidad se controla con constraint trigger diferido.",
    "Descartado: tabla única con NULLs y CHECKs; 4 tablas sin supertipo.",
]
right = [
    "Descartada la jerarquía empleado_sala / encargado_regional.",
    "UK (cuit, tipo) como destino de la FK compuesta.",
    "`localidad` FK (cuit_encargado, tipo_encargado) + CHECK fijo.",
    "El CHECK fija `tipo_encargado` en `encargado_regional`.",
    "1:N: un empleado trabaja en una sola sala (FK NOT NULL).",
]
h = max(panel_height(left, 5.82), panel_height(right, 5.82))
y = centered(h, bottom=5.55)
panels_row(s, y, [
    {"title": "Cliente: supertipo + subtipos", "items": left, "accent": GOLD},
    {"title": "Empleado: una sola tabla", "items": right, "accent": GREEN},
], h=h)
callout(s, "La jerarquía evita NULLs y permite una única FK desde comprobante.", 5.85, 12.6)
footer(s, 7, "001_esquema.sql · Justificación de diseño")
notes(s, "La jerarquía de cliente es total y disjunta. La disyunción se garantiza con la FK compuesta (id, tipo): cada subtipo fija su tipo con un CHECK y la FK exige que ese par exista en cliente. La totalidad no la puede garantizar una FK, por eso va un constraint trigger diferido. En empleado se descartó la jerarquía porque no hay atributos distintos; el tipo es un ENUM y la UK (cuit, tipo) permite validar el rol del encargado desde localidad.")

# ---------------------------------------------------------------------------
# 8. 002 constraints
# ---------------------------------------------------------------------------
s = base("Migración 002", "Constraints: la regla en el esquema")
specs = [
    {"title": "CHECK", "accent": GOLD,
     "desc": "Dominio: precio > 0, graduación 5–20, cantidades y superficies > 0, descuento 0–1.\nSe evalúa fila a fila, en cada INSERT o UPDATE."},
    {"title": "UNIQUE", "accent": GREEN,
     "desc": "Vino (nombre, añada, volumen); documento activo del cliente; parcela por campaña.\nTambién sirve como destino de una FK."},
    {"title": "FK y acciones", "accent": GOLD,
     "desc": "CASCADE solo si la hija no existe sin el padre; RESTRICT para el historial (RN-14). SET NULL no se usó."},
    {"title": "Lo que no puede un constraint", "accent": GREEN,
     "desc": "Mirar otras filas (stock), la fecha actual o una transición de estados: eso va en trigger."},
]
h = max(card_height(x["title"], x["desc"], 5.82, 11.6) for x in specs)
y = centered(2 * h + 0.18, bottom=5.6)
cards_row(s, y, specs[:2], h=h, size=11.6)
cards_row(s, y + h + 0.18, specs[2:], h=h, size=11.6)
callout(s, "Regla fila a fila → constraint. Regla que depende de otras filas o del momento → trigger.", 5.9, 12.6)
footer(s, 8, "002_constraints.sql")
notes(s, "El constraint es declarativo, se ejecuta siempre y no se puede saltear. CHECK y UNIQUE alcanzan cuando la regla se decide con la fila. No alcanzan cuando hay que mirar otras filas (stock), el momento (fecha actual) o una secuencia de estados (transición): ahí entran los triggers. Las acciones de FK también son reglas: RESTRICT protege el historial (RN-14).")

# ---------------------------------------------------------------------------
# 9. 003 funciones
# ---------------------------------------------------------------------------
s = base("Migración 003", "Funciones: cálculo con nombre propio")
left = [
    "`fn_descuento_cliente`: CASE por tipo + descuento especial.",
    "`fn_total_comprobante`: suma renglones y aplica descuento.",
    "`fn_stock_sala`: cantidad o 0 con COALESCE.",
    "`fn_transicion_valida`: confección → terminado → procesado.",
    "`fn_validar_composicion_vino`: suma exactamente 100.",
    "`fn_validar_subtipo_cliente`: un cliente, un subtipo.",
]
right = [
    "**IMMUTABLE:** solo depende de parámetros (transición).",
    "**STABLE:** lee datos, no los modifica (descuento, stock).",
    "**VOLATILE:** no se usa para cálculos repetibles.",
    "Se usan en triggers, procedimientos, vistas y tests.",
    "No reemplazan al constraint: evitan repetir lógica.",
]
h = max(panel_height(left, 5.82), panel_height(right, 5.82))
y = centered(h, bottom=5.55)
panels_row(s, y, [
    {"title": "Qué encapsulan", "items": left, "accent": GOLD},
    {"title": "Volatilidad y uso", "items": right, "accent": GREEN},
], h=h)
callout(s, "La función no reemplaza al constraint: encapsula un cálculo o validación reutilizable.", 5.85, 12.6)
footer(s, 9, "003_funciones.sql")
notes(s, "La función evita repetir la misma lógica en triggers, procedimientos, vistas y tests. La volatilidad no es un detalle: STABLE dice que lee datos pero no los cambia; IMMUTABLE que solo depende de sus parámetros. fn_descuento_cliente resuelve la dependencia transitiva del descuento; fn_validar_composicion_vino valida el 100 % y se invoca desde un constraint trigger diferido.")

# ---------------------------------------------------------------------------
# 10. 004 procedimientos
# ---------------------------------------------------------------------------
s = base("Migración 004", "Procedimientos: una operación completa")
specs = [
    {"title": "p_procesar_ingreso", "accent": GOLD,
     "desc": "FOR UPDATE, estado terminado, exige renglones y hace upsert en `stock_deposito`.\nEvita el doble procesamiento."},
    {"title": "p_procesar_transferencia", "accent": GREEN,
     "desc": "Descuenta depósito, acredita sala y valida stock y estado.\nEvita dejar stock en negativo."},
    {"title": "p_crear_cliente", "accent": GOLD,
     "desc": "Inserta supertipo y subtipo en una sola transacción. `p_cambiar_tipo_cliente` mueve de subtipo sin dejar huérfanos."},
]
h = max(card_height(x["title"], x["desc"], 3.85, 11.4) for x in specs)
y = centered(h + 0.2 + 1.45, bottom=5.55)
cards_row(s, y, specs, h=h, size=11.4)
panels_row(s, y + h + 0.2, [{
    "title": "Por qué en la base",
    "items": [
        "Son varias sentencias que deben ser atómicas: lock + validación + escritura.",
        "La API no puede garantizar concurrencia por sí sola; el procedimiento sí.",
    ],
    "accent": GREEN,
}], h=1.45)
callout(s, "El procedimiento es una operación de negocio atómica; la API solo hace CALL.", 5.85, 12.6)
footer(s, 10, "004_procedimientos.sql")
notes(s, "Un procedimiento no es un CRUD: es una operación completa. p_procesar_ingreso bloquea la cabecera, valida que esté terminada, exige renglones y actualiza el depósito. Si dos sesiones intentan procesar el mismo ingreso, el FOR UPDATE las serializa. La API solo ejecuta CALL y traduce el error.")

# ---------------------------------------------------------------------------
# 11. 005 triggers
# ---------------------------------------------------------------------------
s = base("Migración 005", "Triggers: la regla que ve la transacción")
left = [
    "# 1. BEFORE INSERT: valida stock en la sala (RN-09).",
    "# 2. AFTER INSERT: descuenta stock y recalcula totales (RN-08).",
    "# 3. Si algo falla: excepción y rollback completo.",
    "# 4. La API no envía totales: los pone la base.",
]
right = [
    "Transiciones de estado (RN-10 y RN-11).",
    "Renglones inmutables fuera de confección (RN-12).",
    "Fecha de confección fija (RN-11).",
    "Auditoría de precio (RN-13) y composición 100 (RN-05).",
    "Todo cliente cumple: API, psql o script.",
]
h = max(panel_height(left, 5.82), panel_height(right, 5.82))
y = centered(h, bottom=5.55)
panels_row(s, y, [
    {"title": "Venta, paso a paso", "items": left, "accent": GOLD},
    {"title": "Otras reglas en triggers", "items": right, "accent": GREEN},
], h=h)
callout(s, "El trigger no es magia: es una regla que necesita ver la fila y el estado de la transacción.", 5.85, 12.6)
footer(s, 11, "005_triggers.sql")
notes(s, "El trigger sigue el modelo evento–condición–acción. BEFORE valida antes de escribir; AFTER actualiza stock y totales en la misma transacción. La ventaja es que cualquier cliente, incluso psql, cumple la regla. El costo es la lógica oculta: se mitiga con COMMENT y con los 133 tests. Si falla el stock, no queda comprobante a medias.")

# ---------------------------------------------------------------------------
# 12. 006 vistas
# ---------------------------------------------------------------------------
s = base("Migración 006", "Vistas: definir una vez, leer siempre")
specs = [
    {"title": "vista_stock_total_por_vino", "accent": GOLD,
     "desc": "Depósito + salas con LEFT JOIN y COALESCE.\nEl vino sin stock aparece con cero."},
    {"title": "vista_ventas_mensuales_por_sala", "accent": GREEN,
     "desc": "Agregación mensual para reportes.\nUna sola definición del indicador."},
    {"title": "vista_documentos_pendientes", "accent": GOLD,
     "desc": "Ingresos y transferencias sin procesar.\nEs la bandeja de trabajo."},
]
h = max(card_height(x["title"], x["desc"], 3.85, 11.4) for x in specs)
y = centered(h + 0.2 + 1.45, bottom=5.55)
cards_row(s, y, specs, h=h, size=11.4)
panels_row(s, y + h + 0.2, [{
    "title": "Qué defender",
    "items": [
        "Una vista no guarda datos: guarda la definición; siempre muestra el estado actual.",
        "El LEFT JOIN mantiene los vinos sin stock; no se materializa porque los datos son operativos.",
    ],
    "accent": GREEN,
}], h=1.45)
callout(s, "La vista no duplica datos: duplica la definición una sola vez.", 5.85, 12.6)
footer(s, 12, "006_vistas.sql · 3 vistas")
notes(s, "La vista encapsula el join y la suma de stock para que la ficha y los reportes usen la misma métrica. LEFT JOIN y COALESCE garantizan que un vino sin stock aparezca con cero. No se eligió una vista materializada porque los datos cambian seguido y el costo de refresco no se justifica.")

# ---------------------------------------------------------------------------
# 13. 007 roles
# ---------------------------------------------------------------------------
s = base("Migración 007", "Roles: privilegio mínimo")
left = [
    "DML sobre las 29 tablas operativas.",
    "SELECT e INSERT en `auditoria_precio`.",
    "EXECUTE de funciones y procedimientos.",
    "Nunca se conecta como owner.",
    "La API reporta `current_user = rol_api`.",
]
right = [
    "Solo SELECT sobre las 3 vistas.",
    "Sin acceso directo a las tablas base.",
    "Claves por entorno: APP_DB_PASSWORD.",
    "Un error o una inyección dañan menos.",
]
h = max(panel_height(left, 5.82), panel_height(right, 5.82))
y = centered(h, bottom=5.55)
panels_row(s, y, [
    {"title": "rol_api", "items": left, "accent": GOLD},
    {"title": "rol_reporte", "items": right, "accent": GREEN},
], h=h)
callout(s, "El privilegio mínimo limita el daño de un error o de una inyección.", 5.85, 12.6)
footer(s, 13, "007_roles.sql · db/initdb/99_password_api.sql")
notes(s, "La API se conecta con rol_api, no con el dueño del esquema. rol_reporte solo lee vistas. Las claves no están en el repositorio: se toman del entorno. Esto no reemplaza las reglas de negocio, pero reduce el alcance de un error. El endpoint /salud permite verificar con qué usuario se conecta.")

# ---------------------------------------------------------------------------
# 14. 008 índices
# ---------------------------------------------------------------------------
s = base("Migración 008", "Índices: medir antes de crear")
table(s, 0.75, 1.55, 6.4, 1.95, [
    ["Consulta", "Antes", "Después", "Mejora"],
    ["S3", "9,753 ms", "0,977 ms", "10,0×"],
    ["S8", "15,490 ms", "9,174 ms", "1,69×"],
    ["S9", "77 buf", "3 buf", "25,7×"],
], [2.0, 1.5, 1.5, 1.4], 11)
panels_row(s, 3.75, [{
    "title": "Cómo se mide",
    "items": [
        "`EXPLAIN (ANALYZE, BUFFERS)` antes y después.",
        "Se comparan planes y buffers, no sensaciones.",
        "Se documenta también lo que no mejoró.",
    ],
    "accent": GOLD,
}], total_w=6.4, h=1.9)
panels_row(s, 1.55, [{
    "title": "Qué defender",
    "items": [
        "B-tree: igualdad, rango y orden.",
        "S3 (sala, fecha) + INCLUDE: Index Only Scan.",
        "S8 (fecha, sala) + INCLUDE (total): cobertura.",
        "Parcial: transferencias pendientes. Expresión: lower(nombre).",
        "No todos ayudan: S1, S11 y S12 siguen con Seq Scan.",
    ],
    "accent": GREEN,
}], x=7.4, total_w=5.2, h=4.1)
callout(s, "El índice se justifica con el plan y los buffers, no con la intuición.", 5.9, 12.6)
footer(s, 14, "008_indices.sql · docs/informe_etapa4_indices.md")
notes(s, "El orden de columnas depende de la consulta: en S3 primero la igualdad (sala) y después el rango (fecha); en S8 al revés porque el filtro es un rango de fecha. INCLUDE permite resolver la consulta sin visitar el heap. Los índices parciales y de expresión sirven para casos puntuales. Lo importante: se mide con EXPLAIN (ANALYZE, BUFFERS) y se documenta también lo que no mejoró.")

# ---------------------------------------------------------------------------
# 15. Reglas I
# ---------------------------------------------------------------------------
s = base("Reglas de negocio", "RN-01 a RN-08: qué mecanismo y por qué")
table(s, 0.75, 1.55, 11.85, 4.3, [
    ["Regla", "Qué exige", "Mecanismo"],
    ["RN-01", "Precio del vino mayor que 0", "CHECK"],
    ["RN-02", "Sala → localidad → encargado regional", "FK + CHECK del tipo"],
    ["RN-03", "Cada empleado trabaja en una sola sala", "FK NOT NULL"],
    ["RN-04", "Parcela: una cepa y una cosecha por campaña", "FK + UNIQUE"],
    ["RN-05", "La composición del vino suma 100", "Función + trigger diferido"],
    ["RN-06", "Descuento según tipo de cliente", "Función + CHECK"],
    ["RN-07", "Vencimiento del permiso posterior a la emisión", "CHECK"],
    ["RN-08", "Total del comprobante calculado", "Trigger + función + CHECK"],
], [1.15, 6.9, 3.8], 11.2)
callout(s, "La regla se valida donde no se puede saltear: por eso la base y no la API.", 6.0, 12.6)
footer(s, 15, "002_constraints.sql · 003_funciones.sql · 005_triggers.sql")
notes(s, "RN-01, 07 y 08 se resuelven con constraints porque se deciden con la fila. RN-05 necesita ver todas las filas del vino, por eso función más constraint trigger diferido. RN-02 usa una FK compuesta y un CHECK para fijar el rol. RN-03 es una FK NOT NULL: el empleado siempre pertenece a una sala. RN-04 combina FK con UNIQUE (campaña, parcela, finca).")

# ---------------------------------------------------------------------------
# 16. Reglas II
# ---------------------------------------------------------------------------
s = base("Reglas de negocio", "RN-09 a RN-15: qué mecanismo y por qué")
table(s, 0.75, 1.55, 11.85, 3.85, [
    ["Regla", "Qué exige", "Mecanismo"],
    ["RN-09", "No vender más que el stock de la sala", "CHECK + trigger BEFORE"],
    ["RN-10", "Solo un ingreso terminado impacta el depósito", "Trigger + procedimiento"],
    ["RN-11", "Transferencia, fecha de confección y stock", "Trigger + procedimiento"],
    ["RN-12", "Renglones inmutables fuera de confección", "Trigger"],
    ["RN-13", "Todo cambio de precio queda auditado", "Trigger AFTER"],
    ["RN-14", "No borrar entidades con movimientos", "FK ON DELETE RESTRICT"],
    ["RN-15", "Rangos y valores positivos", "CHECK"],
], [1.15, 6.9, 3.8], 11.2)
callout(s, "Si la regla depende de otras filas o del momento, el constraint no alcanza: va trigger.", 5.7, 12.6)
footer(s, 16, "002_constraints.sql · 004_procedimientos.sql · 005_triggers.sql")
notes(s, "RN-09 tiene dos capas: el CHECK evita stock negativo y el trigger BEFORE rechaza la venta sin stock. RN-10 y RN-11 combinan trigger de transición con procedimiento que aplica el efecto. RN-12 y RN-13 son triggers puros. RN-14 se resuelve con acciones de FK. RN-15 es dominio puro: CHECK. La pregunta clave es siempre por qué ese mecanismo y no otro.")

# ---------------------------------------------------------------------------
# 17. Guarda vs calcula
# ---------------------------------------------------------------------------
s = base("Diseño", "Qué se guarda y qué se calcula")
table(s, 0.75, 1.55, 11.85, 3.95, [
    ["Atributo", "¿Se guarda?", "Consistencia"],
    ["Descuento del cliente", "No", "fn_descuento_cliente"],
    ["descuento_especial", "Sí, solo exportador", "CHECK 0.30–0.35"],
    ["subtotal_renglon", "Sí", "Columna generada"],
    ["subtotal / descuento / total", "Sí", "Trigger + CHECK"],
    ["Campaña del lote", "Sí", "Columna generada"],
    ["Antigüedad", "No", "fn_antiguedad_anios"],
    ["stock_total", "No", "Vista"],
], [4.4, 3.4, 4.05], 11.2)
callout(s, "Guardar un derivado se paga con mantenimiento; se acepta por historial o performance.", 5.8, 12.6)
footer(s, 17, "Justificación de diseño · funciones, vistas y triggers")
notes(s, "La regla general: si el dato se puede calcular y no aporta historial, no se guarda. Se guarda cuando hay una razón concreta: subtotal_renglon conserva el precio histórico; los totales del comprobante evitan agregar sobre 500.000 renglones; campaña se guarda porque RN-04 pide un UNIQUE y un UNIQUE necesita columna. Cada derivado guardado tiene un mecanismo que lo mantiene consistente.")

# ---------------------------------------------------------------------------
# 18. Decisiones y alternativas
# ---------------------------------------------------------------------------
s = base("Diseño", "Decisiones y alternativas descartadas")
table(s, 0.75, 1.55, 11.85, 4.1, [
    ["Decisión", "Alternativa descartada", "Por qué"],
    ["Cliente: supertipo + subtipos", "Tabla única o 4 tablas sueltas", "Evita NULLs y permite una FK única"],
    ["Empleado: tabla única + ENUM", "Jerarquía de roles", "No hay atributos distintos"],
    ["Maridaje: N:M", "Columna multivaluada", "Un maridaje se comparte entre vinos"],
    ["Cliente–sala: vía comprobante", "N:M directa", "Evita pares sin comprobante"],
    ["Ingreso–bodega: FK directa", "Deducirla del vino", "La cabecera la necesita y RN-14"],
    ["Stock: 1:1 con vino", "Entidad depósito", "Hay un solo depósito"],
    ["Precio: guardado en el renglón", "Calcularlo al leer", "Conserva el histórico"],
], [4.2, 3.9, 3.75], 11.0)
callout(s, "La alternativa descartada también se estudia: muestra que la decisión fue una elección.", 5.9, 12.6)
footer(s, 18, "Justificación de diseño · DER/MER")
notes(s, "Cada decisión tiene una alternativa que se evaluó y se descartó por una razón concreta. La tabla única de cliente genera NULLs y CHECKs; las 4 tablas sin supertipo impiden una FK única desde comprobante. Cliente–sala N:M permitiría pares sin respaldo. La bodega del ingreso no se deduce del vino porque la cabecera la necesita antes de los renglones. El precio se guarda para conservar el histórico.")

# ---------------------------------------------------------------------------
# 19. API
# ---------------------------------------------------------------------------
s = base("La API, muy por arriba", "Capa fina: la regla no vive acá")
left = [
    "Front Nginx → API FastAPI → PostgreSQL.",
    "SQL parametrizado en `repositories`; sin ORM.",
    "Traduce SQLSTATE a HTTP (409, 400, etc.).",
    "Abre una transacción por operación.",
]
right = [
    "No calcula totales ni descuentos.",
    "No valida stock ni transiciones.",
    "No decide reglas: las delega en la base.",
    "`/salud` confirma `current_user = rol_api`.",
]
h = max(panel_height(left, 5.82), panel_height(right, 5.82))
y = centered(h, bottom=5.55)
panels_row(s, y, [
    {"title": "Qué hace", "items": left, "accent": GOLD},
    {"title": "Qué no hace", "items": right, "accent": GREEN},
], h=h)
callout(s, "Si la pregunta es de API: capa fina, sin reglas de negocio.", 5.85, 12.6)
footer(s, 19, "api/app/repositories · docs/api/openapi.json")
notes(s, "La API no usa ORM: el SQL vive en repositories. Su trabajo es validar formato, armar la llamada y traducir el error de PostgreSQL a HTTP. No calcula totales ni stock; eso lo hace la base. Si preguntan por la arquitectura, alcanza con esta idea: la regla está en el lugar donde no se puede saltear.")

# ---------------------------------------------------------------------------
# 20. Preguntas I
# ---------------------------------------------------------------------------
s = base("Oral", "Preguntas probables I")
pairs = [
    ("¿Por qué cliente tiene UK (id, tipo)?", "Es el destino de la FK compuesta de cada subtipo; garantiza que el tipo coincida y que un cliente esté en una sola subtabla."),
    ("¿Por qué no una sola tabla cliente?", "La mayoría de las filas tendría NULLs; los subtipos tienen atributos propios y el descuento especial solo aplica a exportador."),
    ("¿Cómo aseguran que todo cliente tenga subtipo?", "Con un constraint trigger diferido que, al cerrar la transacción, verifica que exista la fila del subtipo."),
    ("¿Dónde evitaron una dependencia parcial?", "En composición y en los renglones. El descuento se movió del renglón al comprobante para respetar 2FN."),
    ("¿Por qué guardan totales derivados?", "Por performance e histórico; los mantiene un trigger y un CHECK entre columnas de la misma fila."),
    ("¿Por qué el precio está en el renglón?", "Porque el precio del vino cambia; el comprobante debe conservar el precio con el que se vendió."),
]
qa_list(s, 0.75, centered(qa_height(pairs, 11.6), bottom=6.3, bias=0.35), 11.6, pairs)
footer(s, 20)
notes(s, "Estas son las preguntas más probables sobre el modelo. La respuesta corta primero y después el archivo o la regla. Si la pregunta es de normalización, conviene dibujar la DF en voz alta: (comprobante, vino) → cantidad, precio; id → tipo → descuento.")

# ---------------------------------------------------------------------------
# 21. Preguntas II
# ---------------------------------------------------------------------------
s = base("Oral", "Preguntas probables II")
pairs = [
    ("¿Cuándo hace falta una tabla intermedia?", "Cuando la relación es N:M o cuando tiene atributos propios, como el porcentaje de composición o la cantidad de stock."),
    ("¿Por qué stock_sala tiene PK compuesta?", "Porque la cantidad depende del par sala + vino; ninguna de las dos columnas identifica sola la fila."),
    ("¿Constraint o trigger?", "Constraint si la regla se decide fila a fila; trigger si necesita otras filas, la fecha actual o una transición."),
    ("¿Por qué el stock se controla en la base?", "Porque cualquier cliente puede conectarse y la validación debe ser atómica con la venta: si falla, rollback."),
    ("¿Por qué ese orden de columnas en el índice?", "Primero la igualdad o el rango según la consulta; INCLUDE agrega columnas para resolver con Index Only Scan."),
    ("¿Qué alternativa descartaron?", "Cliente–sala N:M, depósito como entidad y jerarquía de empleado. Cada una tenía una razón de negocio."),
]
qa_list(s, 0.75, centered(qa_height(pairs, 11.6), bottom=6.3, bias=0.35), 11.6, pairs)
footer(s, 21)
notes(s, "Si la pregunta es '¿por qué acá?', la respuesta siempre tiene tres partes: qué necesita la regla (fila, otras filas, tiempo o transacción), qué mecanismo lo resuelve y qué alternativa se descartó. Ese formato muestra razonamiento, no memoria.")

# ---------------------------------------------------------------------------
# 22. Checklist
# ---------------------------------------------------------------------------
s = base("Cierre", "Checklist para el oral")
left = [
    "La jerarquía de cliente y su UK (id, tipo).",
    "Por qué cada regla está donde está.",
    "El flujo completo de una venta.",
    "Qué se guarda y qué se calcula.",
    "El plan de S3 y por qué baja.",
]
right = [
    "Camila: modelo, normalización y 001–003.",
    "Juliana: reglas, 004–008 y demo.",
    "Las dos: demo y cierre.",
    "Ensayo: 3 corridas de 12 minutos.",
]
h = max(panel_height(left, 5.82), panel_height(right, 5.82))
y = centered(h, bottom=5.3)
panels_row(s, y, [
    {"title": "Cada uno puede explicar", "items": left, "accent": GOLD},
    {"title": "Reparto sugerido", "items": right, "accent": GREEN},
], h=h)
callout(s, "No memoricen: sepan ubicar el archivo, la regla y la decisión.", 5.65, 13.5)
footer(s, 22, "Bodegas del Atuel · TPI Bases de Datos")
notes(s, "El objetivo del ensayo no es recitar: es poder ubicar rápido la decisión y el archivo. Si una pregunta no se sabe, conviene responder con el criterio: qué entidad es, qué regla la protege y dónde vive. Eso demuestra comprensión del modelo.")

OUT.parent.mkdir(parents=True, exist_ok=True)


def rebalance(slide) -> None:
    """Centra el bloque de contenido y pega la banda de cierre debajo."""
    co = [sh for sh in slide.shapes if sh.name == "co"]
    content = [sh for sh in slide.shapes if sh.name not in ("hdr", "ftr", "co")]
    if not content or not any(sh.name == "hdr" for sh in slide.shapes):
        return
    top = min(sh.top for sh in content)
    bottom = max(sh.top + sh.height for sh in content)
    if not co:
        dy = Inches(1.55) + max(0, (Inches(6.45) - Inches(1.55) - (bottom - top)) // 2) - top
        for sh in content:
            sh.top = sh.top + dy
        return
    co_top = min(sh.top for sh in co)
    co_bottom = max(sh.top + sh.height for sh in co)
    group = (bottom - top) + Inches(0.42) + (co_bottom - co_top)
    avail = Inches(6.9) - Inches(1.55)
    dy = Inches(1.55) + max(0, (avail - group) // 2) - top
    for sh in content:
        sh.top = sh.top + dy
    target = top + dy + (bottom - top) + Inches(0.42)
    co_dy = target - co_top
    for sh in co:
        sh.top = sh.top + co_dy


for slide in prs.slides:
    rebalance(slide)

prs.save(OUT)
print(f"Guía generada: {OUT}")
print(f"Slides: {len(prs.slides)}")
