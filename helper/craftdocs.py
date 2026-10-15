#!/usr/bin/env python3
"""Erzeugt .docx-, .pdf-, .pptx- und .xlsx-Dateien für Helferlein.

Liest ein JSON-Objekt von stdin und gibt den Pfad der erstellten Datei auf stdout aus.

  {"kind": "docx", "title": "...", "sections": [{"heading": "...", "text": "..."}], "out_dir": "..."}
  {"kind": "pdf",  "title": "...", "sections": [{"heading": "...", "text": "..."}], "out_dir": "..."}
  {"kind": "pptx", "title": "...", "slides": [{"title": "...", "bullets": ["..."]}], "out_dir": "..."}
  {"kind": "xlsx", "title": "...", "columns": ["..."], "rows": [["..."]], "out_dir": "..."}
"""
import datetime
import html
import json
import os
import re
import sys

from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from docx.shared import Pt
from pptx import Presentation
from pptx.enum.lang import MSO_LANGUAGE_ID
from pptx.util import Inches, Pt as PptPt
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import ListFlowable, ListItem, Paragraph, SimpleDocTemplate, Spacer

BULLET_RE = re.compile(r"^\s*(?:[-•*–]|\d+[.)])\s+")


DEFAULT_LANG = "de-DE"


def lang_tag(payload: dict) -> str:
    """Sprache der Texte als BCP-47-Tag (de-AT, de-DE, de-CH …); bestimmt die Rechtschreibprüfung in Word/WordCraft."""
    tag = str(payload.get("lang") or DEFAULT_LANG).replace("_", "-")
    return tag if re.match(r"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$", tag) else DEFAULT_LANG


def set_docx_language(doc, tag: str) -> None:
    """Setzt die Sprache in den Dokument-Standards und allen Absatz-/Zeichenformaten."""
    def apply(rpr):
        lang = rpr.find(qn("w:lang"))
        if lang is None:
            lang = OxmlElement("w:lang")
            rpr.append(lang)
        lang.set(qn("w:val"), tag)
        lang.set(qn("w:eastAsia"), tag)
    defaults = doc.styles.element.find(qn("w:docDefaults"))
    if defaults is not None:
        rpr_default = defaults.find(qn("w:rPrDefault"))
        if rpr_default is None:
            rpr_default = OxmlElement("w:rPrDefault")
            defaults.insert(0, rpr_default)
        rpr = rpr_default.find(qn("w:rPr"))
        if rpr is None:
            rpr = OxmlElement("w:rPr")
            rpr_default.append(rpr)
        apply(rpr)
    for style in doc.styles:
        if style.type in (1, 2):  # Absatz- und Zeichenformate
            apply(style.element.get_or_add_rPr())


PPTX_LANGS = {"de-AT": MSO_LANGUAGE_ID.GERMAN_AUSTRIA, "de-CH": MSO_LANGUAGE_ID.SWISS_GERMAN,
              "de-LI": MSO_LANGUAGE_ID.GERMAN_LIECHTENSTEIN, "de-LU": MSO_LANGUAGE_ID.GERMAN_LUXEMBOURG}


def pptx_language(tag: str):
    if tag in PPTX_LANGS:
        return PPTX_LANGS[tag]
    return MSO_LANGUAGE_ID.GERMAN if tag.lower().startswith("de") else MSO_LANGUAGE_ID.NONE


def safe_filename(title: str) -> str:
    name = re.sub(r'[\\/:*?"<>|\n\r\t]+', " ", title or "").strip()
    name = re.sub(r"\s+", " ", name)[:80].strip(" .")
    return name or "Dokument"


def unique_path(out_dir: str, base: str, ext: str) -> str:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{base}.{ext}")
    n = 2
    while os.path.exists(path):
        path = os.path.join(out_dir, f"{base} {n}.{ext}")
        n += 1
    return path


def add_text_block(doc, text: str) -> None:
    """Absätze durch Leerzeilen, Listenpunkte mit '- ' oder '1.'; einzelne Zeilenumbrüche bleiben erhalten."""
    for block in re.split(r"\n\s*\n", (text or "").strip()):
        lines = [l for l in block.split("\n") if l.strip()]
        if not lines:
            continue
        if all(BULLET_RE.match(l) for l in lines):
            numbered = all(re.match(r"^\s*\d+[.)]\s+", l) for l in lines)
            style = "List Number" if numbered else "List Bullet"
            for l in lines:
                doc.add_paragraph(BULLET_RE.sub("", l).strip(), style=style)
            continue
        para = doc.add_paragraph()
        for i, line in enumerate(lines):
            run = para.add_run(line.strip())
            if i < len(lines) - 1:
                run.add_break()


def build_docx(payload: dict) -> str:
    title = (payload.get("title") or "Dokument").strip()
    doc = Document()
    normal = doc.styles["Normal"]
    normal.font.name = "Calibri"
    normal.font.size = Pt(12)
    set_docx_language(doc, lang_tag(payload))

    sections = payload.get("sections") or []
    # Briefe haben keine Überschriften – dann auch keinen großen Titel drüber
    is_letter = sections and all(not (s.get("heading") or "").strip() for s in sections)
    if not is_letter:
        doc.add_heading(title, level=0)
    for s in sections:
        heading = (s.get("heading") or "").strip()
        if heading:
            doc.add_heading(heading, level=1)
        add_text_block(doc, s.get("text") or "")

    path = unique_path(payload["out_dir"], safe_filename(title), "docx")
    doc.save(path)
    return path


def split_blocks(text: str):
    """Liefert ("bullets"|"numbers"|"para", [zeilen]) je Absatz – gleiche Regeln wie bei docx."""
    for block in re.split(r"\n\s*\n", (text or "").strip()):
        lines = [l for l in block.split("\n") if l.strip()]
        if not lines:
            continue
        if all(BULLET_RE.match(l) for l in lines):
            numbered = all(re.match(r"^\s*\d+[.)]\s+", l) for l in lines)
            yield ("numbers" if numbered else "bullets"), [BULLET_RE.sub("", l).strip() for l in lines]
        else:
            yield "para", [l.strip() for l in lines]


def build_pdf(payload: dict) -> str:
    title = (payload.get("title") or "Dokument").strip()
    sections = payload.get("sections") or []
    is_letter = sections and all(not (s.get("heading") or "").strip() for s in sections)

    styles = getSampleStyleSheet()
    body = styles["BodyText"]
    body.fontSize, body.leading, body.spaceAfter = 11.5, 16, 8
    esc = lambda t: html.escape(t, quote=False)

    story = []
    if not is_letter:
        story += [Paragraph(esc(title), styles["Title"]), Spacer(1, 0.3 * cm)]
    for s in sections:
        heading = (s.get("heading") or "").strip()
        if heading:
            story.append(Paragraph(esc(heading), styles["Heading2"]))
        for kind, lines in split_blocks(s.get("text") or ""):
            if kind == "para":
                story.append(Paragraph("<br/>".join(esc(l) for l in lines), body))
            else:
                items = [ListItem(Paragraph(esc(l), body)) for l in lines]
                story.append(ListFlowable(items, bulletType="1" if kind == "numbers" else "bullet", leftIndent=14))

    path = unique_path(payload["out_dir"], safe_filename(title), "pdf")
    doc = SimpleDocTemplate(path, pagesize=A4, title=title,
                            leftMargin=2.5 * cm, rightMargin=2.2 * cm, topMargin=2.2 * cm, bottomMargin=2.2 * cm)
    doc.build(story or [Spacer(1, 1)])
    return path


def build_pptx(payload: dict) -> str:
    title = (payload.get("title") or "Präsentation").strip()
    prs = Presentation()
    prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)  # 16:9

    language = pptx_language(lang_tag(payload))
    cover = prs.slides.add_slide(prs.slide_layouts[0])
    cover.shapes.title.text = title
    cover.placeholders[1].text = datetime.date.today().strftime("%d.%m.%Y")

    for s in payload.get("slides") or []:
        slide = prs.slides.add_slide(prs.slide_layouts[1])
        slide.shapes.title.text = (s.get("title") or "").strip()
        body = slide.placeholders[1]
        body.width = prs.slide_width - Inches(1.0)
        tf = body.text_frame
        bullets = [BULLET_RE.sub("", b).strip() for b in (s.get("bullets") or []) if b and b.strip()]
        for i, b in enumerate(bullets):
            p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
            p.text = b
            p.font.size = PptPt(24)

    # Sprache an jedem Textstück, damit die Rechtschreibprüfung Deutsch nimmt
    if language != MSO_LANGUAGE_ID.NONE:
        for slide in prs.slides:
            for shape in slide.shapes:
                if shape.has_text_frame:
                    for para in shape.text_frame.paragraphs:
                        for run in para.runs:
                            run.font.language_id = language

    path = unique_path(payload["out_dir"], safe_filename(title), "pptx")
    prs.save(path)
    return path


NUMBER_RE = re.compile(r"^-?(\d{1,3}(\.\d{3})+|\d+)(,\d+)?$|^-?\d+(\.\d+)?$")


def to_cell(value):
    """Zahlen (auch deutsch: 1.234,50 / 12,5 / 12,50 €) werden echte Zahlen, "=..." bleibt Formel."""
    if not isinstance(value, str):
        return value
    v = value.strip()
    if v.startswith("="):
        return v
    num = v.replace("€", "").replace("%", "").strip()
    if num and NUMBER_RE.match(num):
        if "," in num:
            num = num.replace(".", "").replace(",", ".")
        elif num.count(".") > 1 or re.match(r"^-?\d{1,3}(\.\d{3})+$", num):
            num = num.replace(".", "")
        try:
            n = float(num)
            n = int(n) if n.is_integer() and "." not in num else n
            return n / 100 if v.endswith("%") else n
        except ValueError:
            pass
    return v


def build_xlsx(payload: dict) -> str:
    title = (payload.get("title") or "Tabelle").strip()
    columns = [str(c) for c in (payload.get("columns") or [])]
    rows = payload.get("rows") or []

    wb = Workbook()
    ws = wb.active
    ws.title = (re.sub(r"[\[\]:*?/\\]", " ", title)[:31].strip() or "Tabelle")
    if columns:
        ws.append(columns)
        for cell in ws[1]:
            cell.font = Font(bold=True, color="FFFFFF")
            cell.fill = PatternFill("solid", fgColor="F2670A")
            cell.alignment = Alignment(vertical="center")
        ws.freeze_panes = "A2"
    for row in rows:
        ws.append([to_cell(v) for v in (row if isinstance(row, list) else [row])])

    for i, col in enumerate(ws.iter_cols(), start=1):
        width = max((len(str(c.value)) for c in col if c.value is not None), default=8)
        ws.column_dimensions[get_column_letter(i)].width = min(max(width + 2, 8), 60)
        for c in col:
            if isinstance(c.value, float) and not c.number_format.endswith("%"):
                c.number_format = "#,##0.00"

    path = unique_path(payload["out_dir"], safe_filename(title), "xlsx")
    wb.save(path)
    return path


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        if not payload.get("out_dir"):
            raise ValueError("out_dir fehlt")
        kind = payload.get("kind")
        if kind == "docx":
            path = build_docx(payload)
        elif kind == "pdf":
            path = build_pdf(payload)
        elif kind == "pptx":
            path = build_pptx(payload)
        elif kind == "xlsx":
            path = build_xlsx(payload)
        else:
            raise ValueError(f"Unbekannter Typ: {kind!r}")
    except Exception as e:  # Fehler gehen als Text an die App zurück
        print(f"{type(e).__name__}: {e}", file=sys.stderr)
        return 1
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
