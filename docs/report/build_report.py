"""Builds the BCSE302P mini-project report into the faculty's Word template.

Usage: python build_report.py <template.docx> <images dir> <output.docx>
The template's cover page, certificate, styles, margins and footer are kept;
everything from the abstract onward is generated here. Figure numbers are
assigned automatically; text refers to figures as {fig:key}.
"""
import json
import re
import struct
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

TEMPLATE, IMG_DIR, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / 'db' / 'report'

TITLE = 'CampusBite: A Campus Canteen Pre-Order and Pickup System'
SHORT = 'CampusBite'
REPO_BLANK = '______________________________________________'

# --------------------------------------------------------------------------
# XML builders (formatting copied from the template's own paragraphs)
# --------------------------------------------------------------------------
FONT = '<w:rFonts w:ascii="Times New Roman" w:cs="Times New Roman" w:eastAsia="Times New Roman" w:hAnsi="Times New Roman"/>'
MONO = '<w:rFonts w:ascii="Courier New" w:cs="Courier New" w:eastAsia="Courier New" w:hAnsi="Courier New"/>'


def run(text, b=False, i=False, size=24, mono=False, color=None):
    rpr = (MONO if mono else FONT) + ('<w:b/><w:bCs/>' if b else '') + ('<w:i/><w:iCs/>' if i else '')
    if color:
        rpr += f'<w:color w:val="{color}"/>'
    rpr += f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
    return f'<w:r><w:rPr>{rpr}</w:rPr><w:t xml:space="preserve">{escape(text)}</w:t></w:r>'


def rich(text, size=24, base_i=False):
    """**bold** and `code` markup inside body text."""
    out = []
    for part in re.split(r'(\*\*[^*]+\*\*|`[^`]+`)', text):
        if not part:
            continue
        if part.startswith('**'):
            out.append(run(part[2:-2], b=True, i=base_i, size=size))
        elif part.startswith('`'):
            out.append(run(part[1:-1], mono=True, size=size - 3))
        else:
            out.append(run(part, i=base_i, size=size))
    return ''.join(out)


def para(text='', align='both', after=120, before=0, runs=None, keep_next=False, size=24, italic=False):
    ppr = f'<w:spacing w:after="{after}" w:before="{before}" w:line="360"/><w:jc w:val="{align}"/>'
    if keep_next:
        ppr = '<w:keepNext/>' + ppr
    return f'<w:p><w:pPr>{ppr}</w:pPr>{runs if runs is not None else rich(text, size, italic)}</w:p>'


CHAP = {'n': '0'}


def h1(text, chap=None):
    CHAP['n'] = chap or text.split('.')[0]
    return ('<w:p><w:pPr><w:pStyle w:val="Heading1"/><w:pageBreakBefore/><w:spacing w:after="200" w:before="120" w:line="360"/></w:pPr>'
            + run(text, b=True, size=28) + '</w:p>')


def h2(text, chap=None):
    if chap:
        CHAP['n'] = chap
    return ('<w:p><w:pPr><w:pStyle w:val="Heading2"/><w:keepNext/><w:spacing w:after="120" w:before="200" w:line="360"/></w:pPr>'
            + run(text, b=True, size=28) + '</w:p>')


def h3(text):
    return para(runs=run(text, b=True, size=24), align='left', before=120, after=60, keep_next=True)


def bullet(text):
    return ('<w:p><w:pPr><w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr>'
            '<w:spacing w:after="60" w:line="360"/><w:jc w:val="both"/></w:pPr>' + rich(text) + '</w:p>')


def code(src):
    lines = src.rstrip('\n').replace('\t', '    ').split('\n')
    out = []
    for k, line in enumerate(lines):
        spacing = f'<w:spacing w:after="{120 if k == len(lines) - 1 else 0}" w:line="240" w:lineRule="auto"/>'
        out.append(f'<w:p><w:pPr><w:shd w:fill="F2F2F2" w:color="auto" w:val="clear"/>{spacing}</w:pPr>'
                   f'{run(line if line else " ", mono=True, size=18)}</w:p>')
    return ''.join(out)


BORDER = '<w:top w:val="single" w:color="000000" w:sz="4"/><w:left w:val="single" w:color="000000" w:sz="4"/><w:bottom w:val="single" w:color="000000" w:sz="4"/><w:right w:val="single" w:color="000000" w:sz="4"/>'
CELL_MAR = '<w:tcMar><w:top w:type="dxa" w:w="60"/><w:left w:type="dxa" w:w="100"/><w:bottom w:type="dxa" w:w="60"/><w:right w:type="dxa" w:w="100"/></w:tcMar>'


def cell(text, w, head=False, size=20, mono=False, align='left'):
    shade = '<w:shd w:fill="D9E2F3" w:color="auto" w:val="clear"/>' if head else ''
    paras = []
    for line in str(text).split('\n'):
        r = run(line, b=head, size=size, mono=mono) if (head or mono) else rich(line, size)
        paras.append(f'<w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="{align}"/></w:pPr>{r}</w:p>')
    return (f'<w:tc><w:tcPr><w:tcW w:type="dxa" w:w="{w}"/><w:tcBorders>{BORDER}</w:tcBorders>{shade}{CELL_MAR}</w:tcPr>'
            + ''.join(paras) + '</w:tc>')


def table(headers, rows, widths, size=20, mono_cols=(), center_cols=()):
    total = sum(widths)
    grid = ''.join(f'<w:gridCol w:w="{w}"/>' for w in widths)
    xml = (f'<w:tbl><w:tblPr><w:tblW w:type="dxa" w:w="{total}"/><w:jc w:val="center"/><w:tblBorders>'
           '<w:top w:val="single" w:color="auto" w:sz="4"/><w:left w:val="single" w:color="auto" w:sz="4"/>'
           '<w:bottom w:val="single" w:color="auto" w:sz="4"/><w:right w:val="single" w:color="auto" w:sz="4"/>'
           '<w:insideH w:val="single" w:color="auto" w:sz="4"/><w:insideV w:val="single" w:color="auto" w:sz="4"/>'
           f'</w:tblBorders><w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid>{grid}</w:tblGrid>')
    xml += '<w:tr><w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>' + ''.join(cell(h, w, head=True, size=size) for h, w in zip(headers, widths)) + '</w:tr>'
    for r in rows:
        xml += '<w:tr><w:trPr><w:cantSplit/></w:trPr>' + ''.join(
            cell(v, w, size=size, mono=(k in mono_cols), align='center' if k in center_cols else 'left')
            for k, (v, w) in enumerate(zip(r, widths))) + '</w:tr>'
    return xml + '</w:tbl>' + para('', after=60)


def table_caption(num, name):
    return para(runs=run(f'Table {num}: ', b=True) + run(name), align='both', after=80, keep_next=True)


# ----------------------------- images ------------------------------------
IMAGES = []
_img_id = [0]
FIGS = {}
_fig_count = {}


def image_size(data):
    if data[:8] == b'\x89PNG\r\n\x1a\n':
        return struct.unpack('>II', data[16:24])
    i = 2
    while i < len(data):
        marker, seg_len = data[i + 1], struct.unpack('>H', data[i + 2:i + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            h, w = struct.unpack('>HH', data[i + 5:i + 9])
            return w, h
        i += 2 + seg_len
    raise ValueError('unknown image')


def drawing(name, max_w_in, max_h_in=8.6, border=True):
    data = (IMG_DIR / name).read_bytes()
    w, h = image_size(data)
    scale = min(max_w_in / (w / 96), max_h_in / (h / 96))
    cx, cy = int(w / 96 * scale * 914400), int(h / 96 * scale * 914400)
    _img_id[0] += 1
    n = _img_id[0]
    ext = name.rsplit('.', 1)[1].replace('jpeg', 'jpg')
    IMAGES.append((f'word/media/report_img{n}.{ext}', data))
    line = '<a:ln w="6350"><a:solidFill><a:srgbClr val="BFBFBF"/></a:solidFill></a:ln>' if border else ''
    return (f'<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{cx}" cy="{cy}"/>'
            f'<wp:docPr id="{1000 + n}" name="Picture {n}"/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>'
            '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            f'<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="{1000 + n}" name="{escape(name)}"/><pic:cNvPicPr/></pic:nvPicPr>'
            f'<pic:blipFill><a:blip r:embed="rIdImg{n}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
            f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
            f'{line}</pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>')


def fignum(key):
    ch = CHAP['n']
    _fig_count[ch] = _fig_count.get(ch, 0) + 1
    FIGS[key] = f'{ch}.{_fig_count[ch]}'
    return FIGS[key]


def caption(num, text):
    return (f'<w:p><w:pPr><w:spacing w:after="200" w:line="360"/><w:jc w:val="center"/></w:pPr>'
            + run(f'Figure {num}: {text}', i=True, size=22) + '</w:p>')


def figure(key, name, text, width=6.2, max_h=8.4, border=True):
    num = fignum(key)
    return (f'<w:p><w:pPr><w:keepNext/><w:spacing w:before="120" w:after="60" w:line="240" w:lineRule="auto"/><w:jc w:val="center"/></w:pPr>'
            + drawing(name, width, max_h, border) + '</w:p>' + caption(num, text))


def figure_row(key, names, text, width=1.85, max_h=3.75, labels=None):
    num = fignum(key)
    n = len(names)
    col = 9026 // n
    cells = ''
    for k, nm in enumerate(names):
        lab = (f'<w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/><w:jc w:val="center"/></w:pPr>'
               + run(labels[k], i=True, size=19) + '</w:p>').replace('<w:pPr>', '<w:pPr><w:keepNext/>', 1) if labels else ''
        wk = width[k] if isinstance(width, (list, tuple)) else width
        hk = max_h[k] if isinstance(max_h, (list, tuple)) else max_h
        cells += (f'<w:tc><w:tcPr><w:tcW w:type="dxa" w:w="{col}"/><w:vAlign w:val="top"/></w:tcPr>'
                  f'<w:p><w:pPr><w:keepNext/><w:spacing w:after="40" w:line="240" w:lineRule="auto"/><w:jc w:val="center"/></w:pPr>{drawing(nm, wk, hk)}</w:p>{lab}</w:tc>')
    grid = ''.join(f'<w:gridCol w:w="{col}"/>' for _ in names)
    return (f'<w:tbl><w:tblPr><w:tblW w:type="dxa" w:w="{col * n}"/><w:jc w:val="center"/><w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/>'
            f'<w:bottom w:val="nil"/><w:right w:val="nil"/><w:insideH w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders><w:tblLayout w:type="fixed"/></w:tblPr>'
            f'<w:tblGrid>{grid}</w:tblGrid><w:tr><w:trPr><w:cantSplit/></w:trPr>{cells}</w:tr></w:tbl>' + caption(num, text))


# ----------------------------- source extraction --------------------------
def src(path):
    return (ROOT / path).read_text(encoding='utf-8')


def between(text, start, end, include_end=True):
    i = text.index(start)
    j = text.index(end, i + len(start))
    return text[i:j + (len(end) if include_end else 0)]


SCHEMA, TRIG, PKG = src('db/01_schema.sql'), src('db/02_triggers.sql'), src('db/03_package.sql')
SPEC = PKG[:PKG.index('CREATE OR REPLACE PACKAGE BODY')]
BODY = PKG[PKG.index('CREATE OR REPLACE PACKAGE BODY'):]


def create_table(name):
    return between(SCHEMA, f'CREATE TABLE {name} (', '\n);')


def trigger(name):
    return between(TRIG, f'CREATE OR REPLACE TRIGGER {name}', '\n/')


def member(kind, name):
    start = BODY.index(f'  {kind} {name} (')
    end = BODY.index(f'END {name};', start)
    return BODY[start:end + len(f'END {name};')]


def excerpt(text, parts, gap='    ...'):
    """Join selected (start, end) slices of text with '...' between them."""
    out = []
    for s, e in parts:
        out.append(between(text, s, e))
    return ('\n' + gap + '\n').join(out)


def spec_summary():
    """Package specification condensed to one line per member (parameter lists kept)."""
    lines = ['CREATE OR REPLACE PACKAGE canteen_pkg AS']
    for c in re.findall(r'^\s*(c_\w+\s+CONSTANT .*?;.*)$', SPEC, re.M):
        lines.append('  ' + c.strip())
    lines.append('')
    for f in re.findall(r'^\s*(FUNCTION .*?;)\s*$', SPEC, re.M):
        lines.append('  ' + re.sub(r'\s+', ' ', f))
    lines.append('')
    for name, params in re.findall(r'PROCEDURE (\w+) \((.*?)\);', SPEC, re.S):
        ps = [re.sub(r'\s+', ' ', re.sub(r'--.*', '', p)).strip() for p in params.split(',')]
        lines.append(f'  PROCEDURE {name} ({", ".join(p for p in ps if p)});')
    lines.append('END canteen_pkg;')
    return '\n'.join(lines)


def proof_value(file, pattern):
    m = re.search(pattern, (REPORT / file).read_text(encoding='utf-8'))
    return m.group(1) if m else '?'


# --------------------------------------------------------------------------
# Content
# --------------------------------------------------------------------------
B = []
add = B.append

# ======================= 1. INTRODUCTION =======================
add(h1('1. INTRODUCTION'))
add(h2('1.1 Problem Statement'))
add(para('Anyone who has tried to grab lunch between two back-to-back classes knows the problem. Most students reach the food court in the same ten minutes, stand in one line to order and pay, then crowd around the counter waiting for their number to be called. Outlets lose sales because students give up and walk away, and the counter staff spend more time shouting token numbers than cooking. At night the hostel canteen has the opposite problem: food runs out, but nobody finds out until they have already walked there.'))
add(para('Today the outlets handle this with paper tokens, a cash or UPI counter and a notebook for stock. None of these share information. A student cannot see the menu, the queue or whether a dish is still available before leaving the classroom. The vendor cannot see how many orders are coming in the next half hour, and there is no record of which dishes sell best or when stock ran out. Counting the day\'s sales means adding up slips by hand, and paper tokens get lost or picked up by the wrong person.'))
add(para(f'**{SHORT}** addresses this with a shared database behind a mobile-first web app. There are three kinds of users: **students**, who browse menus, pay from a prepaid wallet, book a pickup slot and collect their food with a QR code; **vendors** (outlet owners), who accept and prepare orders, manage their menu and stock and read sales reports; and an **administrator**, who oversees every outlet and user. The project focuses on the database side: the schema, the integrity rules, and PL/SQL program units that enforce the business logic no matter which screen or tool changes the data.'))
add(h2('1.2 Objectives'))
for t in [
    'Design a normalised relational schema (up to 3NF/BCNF) for users, outlets, menus, orders, payments, pickup slots and audit data, with every rule that can be declared written as a PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK, NOT NULL or DEFAULT constraint.',
    'Put all business logic (ordering, wallet payments, coupons, GST, order status changes, cancellation with refund, reviews and reports) in one PL/SQL package, `canteen_pkg`, made of functions and procedures.',
    'Use triggers to enforce rules automatically: daily pickup tokens, a secret pickup code, stock deduction, low-stock alerts, pickup-slot capacity, price history, a status audit trail and loyalty points.',
    'Use cursors (explicit, parameterised, cursor FOR loops, implicit and REF CURSORs) where data has to be handled row by row or passed back to the application.',
    'Keep every multi-step operation atomic, so a failed payment never leaves a half-saved order, deducted stock or lost money.',
    'Build a mobile-first front-end connected to the database through a REST API, and verify every feature with test cases and screenshots.',
]:
    add(bullet(t))
add(h2('1.3 Importance of DBMS'))
add(para('A spreadsheet could store the menu, but it could not keep this system correct once many people use it at the same time. A DBMS helps in the following concrete ways:'))
for t in [
    '**Data integrity.** CHECK constraints stop a negative price, a negative wallet balance or a rating outside 1 to 5. Foreign keys stop an order from pointing to a dish or outlet that does not exist. Triggers enforce rules that span tables, such as reducing stock when an order line is inserted.',
    '**Reduced redundancy.** Normalisation stores each fact once. A dish name lives only in `menu_item` and an outlet\'s location only in `outlet`, so changing either one updates every screen.',
    '**Concurrency control.** At lunch time many students order at once. Row locks (`SELECT ... FOR UPDATE`) on the wallet and dish rows, plus a CHECK constraint on slot bookings, make sure two students can never spend the same balance, buy the last plate twice or overbook a pickup slot.',
    '**Atomicity and recovery.** Placing an order touches seven tables. The procedure works inside a transaction with a savepoint, so either every change is committed or none is.',
    '**Security.** The application never builds SQL from user input. It calls package procedures with bind variables, which rules out SQL injection. Passwords are stored only as salted scrypt hashes, and the pickup code is never shown to vendors.',
    '**Query efficiency.** Indexes on foreign keys and frequent filters keep the live order board and the reports fast. Views such as `v_order_details` let the joins be written once and reused.',
]:
    add(bullet(t))
add(h2('1.4 Scope of the Project'))
add(para('**Included:** student registration and login; outlet listing with live open/closed status and wait time; menu browsing with search, categories and a veg filter; a cart and checkout with coupons, 5% GST and 15-minute pickup slots; wallet top-up and a full transaction ledger; order tracking with a token and a QR code; a vendor order board; QR or 6-digit code verification at pickup; menu, price, stock and slot-capacity management; sales reports, low-stock alerts, price history and daily summaries; an admin overview; ratings and loyalty points.'))
add(para('**Out of scope:** a real payment gateway (wallet top-ups are simulated), delivery to rooms, push notifications when the app is closed, raw-ingredient inventory and staff payroll. The schema is designed so most of these can be added later without changing existing tables.'))

# ======================= 2. SYSTEM REQUIREMENTS =======================
add(h1('2. SYSTEM REQUIREMENTS'))
add(para('The system was developed and tested on my own laptop. The minimum needed to run it is much lower: any machine that can run Oracle XE (about 2 GB of RAM) and a modern browser.'))
add(h2('2.1 Hardware Requirements'))
add(table(['Component', 'Specification'], [
    ['Processor', '13th Gen Intel Core i7-13620H (development machine); Intel Core i3 / AMD Ryzen 3 or above is sufficient'],
    ['RAM', '16 GB (minimum 4 GB; Oracle XE itself uses up to 2 GB)'],
    ['Storage', '512 GB NVMe SSD (the project needs under 2 GB, mostly the Oracle XE installation)'],
    ['Other', 'Any Android or iOS smartphone with a modern browser for the student app; a phone camera for vendor QR scanning'],
], [2600, 6426]))
add(h2('2.2 Software Requirements'))
add(table(['Category', 'Tool / Version'], [
    ['Operating System', 'Windows 11 Home'],
    ['DBMS', 'Oracle Database 21c Express Edition (21.3.0.0.0), pluggable database XEPDB1, schema CANTEEN'],
    ['Query / IDE Tool', 'SQL*Plus 21.3 (all scripts and outputs in this report), Visual Studio Code for editing'],
    ['Front-End Language', 'HTML5, CSS3 and JavaScript (single-page app, installable as a Progressive Web App); qrcodejs 1.0.0 and html5-qrcode 2.3.8 for QR codes'],
    ['Server / Connectivity', 'Node.js 24.14.1, Express 4.22.3, node-oracledb 26.0.0 (Thin mode, no Oracle Client needed), cookie-session 2.1.1'],
    ['Browser', 'Google Chrome 156 (desktop and mobile viewport)'],
    ['Other Tools', 'Graphviz and Mermaid (ER diagrams), Git and GitHub (source code), PowerShell scripts for one-step database rebuild'],
], [2600, 6426]))

# ======================= 3. DATABASE DESIGN =======================
add(h1('3. DATABASE DESIGN'))
add(h2('3.1 Entity–Relationship (ER) Diagram'))
add(para('I started from the nouns in the problem statement: a user places an order at an outlet, the order contains dishes, it is paid from a wallet and picked up in a time slot. That gave the core entities. The supporting entities (status log, price history, stock alert, token counter, daily summary) came later, once I knew which facts the triggers and reports needed to record.'))
add(table_caption('3.1', 'Entities and their key attributes'))
add(table(['Entity', 'Key attribute(s)', 'Purpose'], [
    ['APP_USER', 'user_id (PK); email, reg_no (UNIQUE)', 'Students, vendors and the admin; wallet balance and loyalty points'],
    ['OUTLET', 'outlet_id (PK); name (UNIQUE)', 'A canteen counter, its hours and pickup-slot capacity'],
    ['CATEGORY', 'category_id (PK)', 'Breakfast, Meals, Snacks, Chinese, Beverages, Desserts'],
    ['MENU_ITEM', 'item_id (PK); (outlet_id, name) UNIQUE', 'A dish with price, stock and rating'],
    ['COUPON', 'code (PK)', 'Discount rules and validity'],
    ['PICKUP_SLOT', '(outlet_id, slot_start)', 'Weak entity of OUTLET: a 15-minute window with capacity and bookings'],
    ['ORDERS', 'order_id (PK)', 'One pre-order: token, secret pickup code, status and amounts'],
    ['ORDER_ITEM', '(order_id, item_id)', 'The M:N CONTAINS relationship between ORDERS and MENU_ITEM, with qty and unit_price'],
    ['WALLET_TXN', 'txn_id (PK)', 'Every top-up, payment and refund'],
    ['REVIEW', 'review_id (PK); (order_id, item_id) UNIQUE', 'A 1–5 rating of a dish the student actually picked up'],
    ['Audit / support', 'ORDER_STATUS_LOG, TOKEN_COUNTER, PRICE_HISTORY, STOCK_ALERT, DAILY_SALES_SUMMARY', 'Written by triggers and procedures (Figure {fig:cf2})'],
], [2000, 3200, 3826], size=19))
add(table_caption('3.2', 'Relationships, cardinality and participation'))
add(table(['Relationship', 'Cardinality', 'Participation'], [
    ['APP_USER owns OUTLET', '1 : N', 'Total on OUTLET (every outlet has an owner); partial on APP_USER'],
    ['APP_USER places ORDERS', '1 : N', 'Total on ORDERS; partial on APP_USER'],
    ['OUTLET sells MENU_ITEM; CATEGORY groups MENU_ITEM', '1 : N', 'Total on MENU_ITEM'],
    ['ORDERS contains MENU_ITEM', 'M : N', 'Total on ORDERS (at least one line); partial on MENU_ITEM'],
    ['OUTLET offers PICKUP_SLOT', '1 : N (identifying)', 'Total on PICKUP_SLOT'],
    ['ORDERS booked in PICKUP_SLOT', 'N : 1', 'Total on ORDERS'],
    ['COUPON applied to ORDERS', '1 : N', 'Partial on both sides'],
    ['APP_USER has WALLET_TXN; ORDERS paid by WALLET_TXN', '1 : N', 'Total on WALLET_TXN for the user; partial for orders (a top-up has no order)'],
], [3800, 1600, 3626], size=19))
add(para('The conceptual model is drawn in Chen notation in {fig:chen}, with the notation in {fig:legend}: rectangles are entities, diamonds are relationships, ovals are attributes, a double rectangle and double diamond mark the weak entity PICKUP_SLOT and its identifying relationship, and double lines mark total participation. {fig:cf1} and {fig:cf2} show the same design as logical tables in crow\'s foot notation, split into the ordering side and the outlet/audit side so that every column stays readable.'))
add(figure('legend', 'g05_chen_legend.png', 'Notation used in the Chen ER diagram', width=6.2, max_h=0.6, border=False))
add(figure('chen', 'g04_chen_er_rot.png', f'Conceptual ER diagram of {SHORT} in Chen notation (rotated to use the full page)', width=6.3, max_h=8.7, border=False))
add(figure('cf1', 'g06_cf_ordering.png', 'Logical schema, part 1: ordering, payment and reviews (crow\'s foot notation)', width=5.2, max_h=6.8, border=False))
add(figure('cf2', 'g07_cf_outlets_rot.png', 'Logical schema, part 2: outlets, menu and the audit tables written by triggers (rotated)', width=6.3, max_h=8.6, border=False))

# 3.2 relational schema
add(h2('3.2 Relational Schema'))
add(para('The tables below were generated from Oracle\'s own data dictionary (`user_tab_columns`, `user_constraints`) after the final build, so they match the database exactly. The six central relations are listed column by column; the nine supporting relations are summarised in Table 3.9. "Identity" means the value is generated by Oracle with `GENERATED BY DEFAULT AS IDENTITY`.'))
DICT = json.loads((REPORT / 'dictionary.json').read_text(encoding='utf-8'))
DESC = json.loads((Path(__file__).parent / 'column_notes.json').read_text(encoding='utf-8'))
CORE = ['APP_USER', 'OUTLET', 'MENU_ITEM', 'PICKUP_SLOT', 'ORDERS', 'ORDER_ITEM']


def dtype(c):
    t = c['DATA_TYPE']
    if t in ('VARCHAR2', 'CHAR'):
        return f"{t}({c['DATA_LENGTH']})"
    if t == 'NUMBER':
        if c['DATA_PRECISION'] is None:
            return 'NUMBER'
        return f"NUMBER({c['DATA_PRECISION']}{',' + str(c['DATA_SCALE']) if c['DATA_SCALE'] else ''})"
    return 'TIMESTAMP' if t.startswith('TIMESTAMP') else t


def constraints_of(tname):
    cons = [c for c in DICT['cons'] if c['TABLE_NAME'] == tname]
    by_col = {}
    for c in cons:
        same = [x['COLUMN_NAME'] for x in cons if x['CONSTRAINT_NAME'] == c['CONSTRAINT_NAME']]
        if c['CONSTRAINT_TYPE'] == 'P':
            lab = 'PRIMARY KEY' if len(same) == 1 else 'PRIMARY KEY (composite)'
        elif c['CONSTRAINT_TYPE'] == 'R':
            lab = f"FOREIGN KEY → {c['R_TABLE']}({c['R_COLUMN']})"
        elif c['CONSTRAINT_TYPE'] == 'U':
            lab = 'UNIQUE' if len(same) == 1 else 'UNIQUE (' + ', '.join(u.lower() for u in same) + ')'
        elif c['CONSTRAINT_TYPE'] == 'C' and c['SEARCH_CONDITION_VC']:
            lab = 'CHECK ' + re.sub(r'\s+', ' ', c['SEARCH_CONDITION_VC']).strip()
        else:
            continue
        if lab not in by_col.setdefault(c['COLUMN_NAME'], []):
            by_col[c['COLUMN_NAME']].append(lab)
    return cons, by_col


for k, tname in enumerate(CORE, start=3):
    cols = [c for c in DICT['cols'] if c['TABLE_NAME'] == tname]
    _, by_col = constraints_of(tname)
    rows = []
    for c in cols:
        labs = list(by_col.get(c['COLUMN_NAME'], []))
        if c['NULLABLE'] == 'N' and not any(l.startswith('PRIMARY') for l in labs):
            labs.append('NOT NULL')
        if c['IDENTITY_COLUMN'] == 'YES':
            labs.append('Identity')
        elif c['DATA_DEFAULT'] and c['DATA_DEFAULT'].strip().upper() != 'NULL':
            labs.append('DEFAULT ' + c['DATA_DEFAULT'].strip())
        rows.append([c['COLUMN_NAME'].lower(), dtype(c), '\n'.join(labs), DESC.get(tname, {}).get(c['COLUMN_NAME'].lower(), '')])
    add(table_caption(f'3.{k}', tname))
    add(table(['Attribute', 'Data Type', 'Constraint', 'Description'], rows, [1600, 1750, 3176, 2500], size=18))

SUPPORT = ['CATEGORY', 'COUPON', 'WALLET_TXN', 'REVIEW', 'ORDER_STATUS_LOG', 'TOKEN_COUNTER', 'PRICE_HISTORY', 'STOCK_ALERT', 'DAILY_SALES_SUMMARY']
PURPOSE = {'CATEGORY': 'Menu categories', 'COUPON': 'Discount codes and their limits', 'WALLET_TXN': 'Ledger of every top-up, payment and refund',
           'REVIEW': 'Rating of a dish from a picked-up order', 'ORDER_STATUS_LOG': 'Audit trail (trg_order_status_audit)',
           'TOKEN_COUNTER': 'Last token per outlet per day (trg_order_token)', 'PRICE_HISTORY': 'Old and new prices (trg_menu_price_audit)',
           'STOCK_ALERT': 'Low-stock warnings (trg_menu_stock_watch)', 'DAILY_SALES_SUMMARY': 'End-of-day figures (generate_daily_summary)'}
rows = []
for t in SUPPORT:
    cols = [c for c in DICT['cols'] if c['TABLE_NAME'] == t]
    cons, by_col = constraints_of(t)
    pk = ', '.join(c['COLUMN_NAME'].lower() for c in cons if c['CONSTRAINT_TYPE'] == 'P')
    fks = sorted({f"{c['COLUMN_NAME'].lower()} → {c['R_TABLE'].lower()}" for c in cons if c['CONSTRAINT_TYPE'] == 'R'})
    other = []
    for c in cons:
        if c['CONSTRAINT_TYPE'] == 'U':
            other.append('UNIQUE ' + c['COLUMN_NAME'].lower())
        elif c['CONSTRAINT_TYPE'] == 'C' and c['SEARCH_CONDITION_VC']:
            other.append('CHECK ' + re.sub(r'\s+', ' ', c['SEARCH_CONDITION_VC']).strip())
    rows.append([t, ', '.join(c['COLUMN_NAME'].lower() for c in cols), pk, '\n'.join(fks) or '–', '\n'.join(dict.fromkeys(other)) or '–', PURPOSE[t]])
add(table_caption('3.9', 'Supporting relations (all attributes, keys and constraints)'))
add(table(['Relation', 'Attributes', 'Primary key', 'Foreign keys', 'Other constraints', 'Purpose'], rows,
          [1450, 2300, 1100, 1450, 1550, 1176], size=16))

add(h2('3.3 Schema Definition (DDL)'))
add(para('All fifteen tables are created by `db/01_schema.sql`, which first drops any existing objects so the script can be re-run cleanly. Two representative statements are shown here; the complete script is in the project repository listed on the abstract page. Every constraint is named (`pk_`, `fk_`, `uq_`, `ck_`), which made error messages much easier to read during testing.'))
add(code(create_table('orders')))
add(code(create_table('order_item')))

add(h2('3.4 Normalization'))
add(para('To check the design I started from the single flat table a canteen might keep in a register, with one row per order, and decomposed it step by step.'))
add(code('ORDER_REGISTER(order_id, order_date, student_name, reg_no, email, wallet_balance,\n'
          '               outlet_name, outlet_location, vendor_name,\n'
          '               {item_name, category, price, qty}, coupon_code, discount_pct, total)'))
add(para('The braces mark a repeating group: one order holds several dishes. This relation suffers from all three anomalies. A dish cannot be added to the menu until someone orders it (insertion anomaly). Changing a dish\'s price means editing every row it appears in (update anomaly). Deleting the only order for a dish also loses the dish itself (deletion anomaly).'))
add(para('**Functional dependencies:** FD1 order_id → order_date, reg_no, outlet_name, coupon_code, total; FD2 reg_no → student_name, email, wallet_balance (email → reg_no as well); FD3 outlet_name → outlet_location, vendor_name; FD4 (outlet_name, item_name) → category, price; FD5 (order_id, item_name) → qty, unit price at ordering time; FD6 coupon_code → discount_pct, max_discount, validity.'))
add(para('**1NF.** The repeating group moves into its own rows: each dish of an order becomes one row of `ORDER_ITEM(order_id, item_id, qty, unit_price)`. The text "Masala Dosa x1, Pav Bhaji x2" seen on screen is never stored; the view `v_order_details` builds it with LISTAGG.'))
add(para('**2NF.** In `ORDER_ITEM` the key is (order_id, item_id). Category and current price depend only on the item, part of the key (FD4), so they move to `MENU_ITEM`. Only qty and unit_price need the whole key (FD5). Likewise, student details depend only on the student, so `ORDERS` keeps just `user_id`.'))
add(para('**3NF.** `ORDERS` still contained outlet_name → outlet_location, vendor_name (FD3), a transitive dependency order_id → outlet → location. Outlet details move to `OUTLET`, the vendor becomes `owner_id`, category names move to `CATEGORY` and coupon rules (FD6) to `COUPON`. Surrogate keys replace names as foreign keys, so renaming an outlet touches one row.'))
add(para('**BCNF.** In every final relation each determinant is a candidate key: email and reg_no are declared UNIQUE in `APP_USER`, (outlet_id, name) is UNIQUE in `MENU_ITEM`, and the slot, token-counter and summary tables are determined only by their composite primary keys.'))
add(table_caption('3.10', 'Normalisation summary'))
add(table(['Normal Form', 'Relations', 'Justification'], [
    ['1NF', 'ORDERS, ORDER_ITEM (repeating dish group split into rows)', 'Atomic values; no repeating groups'],
    ['2NF', 'ORDER_ITEM, MENU_ITEM, APP_USER', 'No partial dependency on a composite key'],
    ['3NF', 'OUTLET, CATEGORY, COUPON separated; ORDERS keeps only foreign keys', 'No transitive dependency'],
    ['BCNF', 'All 15 tables', 'Every determinant is a candidate key'],
], [1300, 4200, 3526], size=19))
add(para('**Deliberate, controlled redundancy.** `order_item.unit_price` is a snapshot of the price at the moment of ordering; it is a different fact from today\'s price, and old bills must not change when a vendor edits the menu. `wallet_balance`, `rating_avg` and `pickup_slot.booked` are cached totals of other tables, stored for speed and kept correct only by procedures and triggers.'))

# ======================= 4. IMPLEMENTATION =======================
add(h1('4. IMPLEMENTATION'))
add(para('All program units live in the package `canteen_pkg` (`db/03_package.sql`) and the trigger script `db/02_triggers.sql`. For each object type this chapter gives (a) its purpose, (b) the key part of the code and (c) a SQL*Plus screenshot of it running against the live database. {fig:objects} shows every object VALID after a clean build.'))
add(figure('objects', 'd01_objects.png', 'All schema objects compiled and VALID after running install.sql', width=5.0, max_h=6.6))
add(para('The demo data (`db/04_seed.sql`) is not inserted into `orders` directly. The seed script calls `place_order`, `update_order_status`, `verify_pickup` and `add_review` in a loop for a week of orders, so every row was produced by the same code path the app uses and every trigger fired as it would in real use.'))

add(h2('4.1 Functions'))
add(para('The package has nine functions. Each returns one value (or, for `get_slots`, a set of rows) and can be called from SQL, which is why the API uses them inside SELECT statements.'))
add(table_caption('4.1', 'Functions in canteen_pkg'))
add(table(['Function', 'Returns', 'Purpose'], [
    ['get_wallet_balance(user)', 'NUMBER', 'Wallet balance'],
    ['outlet_is_open(outlet) / is_open_at(outlet, time)', "'Y' / 'N'", 'Open now / open at a given time; handles hours past midnight (18:00–04:00)'],
    ['calc_coupon_discount(code, subtotal)', 'NUMBER', 'Checks expiry, usage limit, minimum order; caps the discount'],
    ['estimate_wait_minutes(outlet)', 'NUMBER', 'Kitchen wait from the live queue (cursor FOR loop)'],
    ['earliest_slot(outlet) / next_available_slot(outlet)', 'DATE', 'First feasible slot / first slot that is not full'],
    ['get_slots(outlet, n)', 'TABLE (pipelined)', 'Next n open slots with capacity and free places'],
    ['is_valid_transition(from, to)', "'Y' / 'N'", 'Order life-cycle rule'],
], [3600, 1500, 3926], size=19, mono_cols=(0,)))
add(code(member('FUNCTION', 'calc_coupon_discount')))
add(para('`get_slots` is a pipelined table function: it returns rows one at a time with PIPE ROW, so it can be queried like a table, `SELECT * FROM TABLE(canteen_pkg.get_slots(3, 6))`. Its core loop:'))
add(code(excerpt(member('FUNCTION', 'get_slots'), [('  FUNCTION get_slots', 'BEGIN'), ('    FOR k IN 0 .. 95 LOOP', 'END get_slots;')])))
add(para('**Proof.** WELCOME20 on ₹300 returns ₹50 (20% would be ₹60, capped at ₹50) and EXAM10 on ₹200 returns ₹20. At the time of the run Night Canteen (opens 18:00) reports closed and Juice Junction open; PLACED → READY is rejected and READY → PICKED_UP allowed. The pipelined function lists the next six Night Canteen slots, starting at its opening time.'))
add(figure('func', 'd04_functions.png', 'Function calls from SQL*Plus, including the pipelined get_slots', width=5.6, max_h=6.6))

add(h2('4.2 Procedures'))
add(table_caption('4.2', 'Procedures in canteen_pkg'))
add(table(['Procedure', 'IN parameters', 'OUT parameters', 'Business operation'], [
    ['place_order', 'user, outlet, cart JSON, coupon, slot, notes', 'order_id, token_no, total', 'Complete checkout in one transaction'],
    ['topup_wallet', 'user, amount, remarks', 'new balance', 'Credit ₹1–₹5,000; TOPUP ledger row'],
    ['update_order_status', 'order, new status, actor', '–', 'Accept / cook / ready / cancel; checks outlet ownership'],
    ['verify_pickup', 'outlet, code, order (from QR), actor', 'order_id, token_no', 'Only way to mark an order PICKED_UP'],
    ['cancel_order', 'order, actor', '–', 'Refund, restore stock, free slot and coupon'],
    ['add_review', 'order, item, user, rating, comments', '–', 'One rating per dish actually picked up'],
    ['generate_daily_summary', 'date', 'outlets processed', 'Explicit-cursor report for every outlet'],
    ['get_low_stock / get_top_items / get_sales_report', 'outlet, threshold / days / dates', 'SYS_REFCURSOR', 'Result sets for the reports screen'],
], [2300, 2600, 1700, 2426], size=19))
add(para('`place_order` is the heart of the system. The cart arrives as JSON and is read through an explicit, parameterised cursor over JSON_TABLE. Triggers assign the token, book the slot, price each line from the menu and deduct stock; the procedure applies the coupon and GST and debits the wallet. Any error rolls back to the savepoint, so nothing is half-saved. Key parts:'))
po = member('PROCEDURE', 'place_order')
add(code(excerpt(po, [
    ('    CURSOR c_cart (cp_json CLOB) IS', 'GROUP BY jt.item_id;'),
    ('    SAVEPOINT sp_place_order;', 'v_user := get_user(p_user_id, TRUE);'),
    ('    -- TRG_ORDER_SLOT books the slot', 'CLOSE c_cart;'),
    ('    v_discount := calc_coupon_discount', "'Order #' || o_order_id);"),
    ('    COMMIT;\n  EXCEPTION', 'END place_order;'),
])))
add(para('**Proof.** Rahul tops up ₹300 and orders two Maggi and one Hot Chocolate from Night Canteen with EXAM10: subtotal ₹140, discount ₹14, GST ₹6.30, total ₹132.30. Night Canteen was still closed at the time of the run, so with no slot chosen the order was booked for the first slot after opening (18:00), which is the pre-order feature at work.'))
add(figure('proc', 'd05_procedure.png', 'topup_wallet and place_order executed from SQL*Plus, with the resulting order and ledger rows', width=6.0, max_h=6.8))
add(para('`verify_pickup` closes a loophole I found in the first version, where a vendor could mark any order as collected with one click. Now `update_order_status` refuses PICKED_UP, and only this procedure can set it after matching the secret code from the student\'s QR:'))
add(code(excerpt(member('PROCEDURE', 'verify_pickup'), [
    ('    IF v_order.outlet_id <> p_outlet_id THEN', "WHERE order_id = v_order.order_id;")])))
add(figure('life', 'd08_lifecycle.png', 'Full order life-cycle through update_order_status and verify_pickup, with the audit log and loyalty points', width=5.6, max_h=6.6))

add(h2('4.3 Packages'))
add(para('Grouping everything in `canteen_pkg` means shared constants (`c_gst_rate`, `c_max_topup`) are defined once, the server needs only one name, and helpers that must not be called directly (`get_user`, `can_manage` and `do_cancel`, which issues refunds) are declared only in the package body, so they are private. The specification, condensed to one line per member:'))
add(code(spec_summary()))
add(para('**Usage.** From SQL*Plus: `EXEC canteen_pkg.topup_wallet(5, 200, NULL, :bal);` or in a query: `SELECT canteen_pkg.outlet_is_open(1) FROM dual;`. From the application, every API route calls the package (Section 5.2). {fig:pkg} lists the public members recorded in the data dictionary; the private helpers do not appear.'))
add(figure('pkg', 'd06_package.png', 'Public members of canteen_pkg: nine functions and ten procedures', width=4.6, max_h=5.4))

add(h2('4.4 Triggers'))
add(para('Triggers enforce rules no matter who changes the data: the app, a test script, or someone typing an UPDATE in SQL*Plus. All nine are row-level; `trg_order_status_audit` is a compound trigger with BEFORE and AFTER EACH ROW sections.'))
add(table_caption('4.3', 'Triggers and where each is proven'))
add(table(['Trigger', 'Event and level', 'Rule enforced', 'Proof'], [
    ['trg_order_token', 'BEFORE INSERT ON orders, row', 'Daily per-outlet token and a random 6-digit pickup code', 'Fig. {fig:trg1}, {fig:p2b}'],
    ['trg_order_slot', 'BEFORE INSERT OR UPDATE OF pickup_slot, status ON orders, row', 'Books, moves and frees slot places; full slot → ORA-20013', 'Fig. {fig:trg1}, {fig:trg2}, {fig:p4b}'],
    ['trg_order_item_stock', 'BEFORE INSERT ON order_item, row', 'Price from the menu; checks outlet, availability, stock; deducts stock', 'Fig. {fig:trg1}, {fig:p2b}'],
    ['trg_menu_stock_watch', 'BEFORE UPDATE OF stock_qty ON menu_item, row', 'Stock 0 hides the dish; ≤ 5 raises an alert; restock re-lists', 'Fig. {fig:trg3}, {fig:p5}'],
    ['trg_menu_price_audit', 'AFTER UPDATE OF price ON menu_item, row', 'Writes price_history', 'Fig. {fig:trg3}, {fig:p5}'],
    ['trg_order_status_audit', 'Compound: INSERT OR UPDATE OF status ON orders', 'Stamps updated_at; logs every status change', 'Fig. {fig:trg2}, {fig:p3}'],
    ['trg_loyalty_points', 'AFTER UPDATE OF status ON orders, row', '1 point per ₹10 when the order is picked up', 'Fig. {fig:trg2}, {fig:p3}'],
    ['trg_wallet_guard', 'BEFORE UPDATE OF wallet_balance ON app_user, row', 'Readable ORA-20010 instead of a negative balance', 'Fig. {fig:trg2}'],
    ['trg_review_rating', 'AFTER INSERT ON review, row', 'Running average rating of the dish', 'Fig. {fig:trg2}, {fig:p3}'],
], [2050, 2700, 2900, 1376], size=17, mono_cols=(0,)))
add(para('My first idea for tokens was MAX(token_no) + 1 from ORDERS inside an ORDERS trigger, which is the classic mutating-table situation and unsafe when two orders arrive together. The final design keeps a separate `token_counter` table updated with MERGE. For slots, the booking is a single UPDATE with `booked < capacity` in the WHERE clause; if the implicit cursor reports no row changed, the slot is full:'))
add(code(excerpt(trigger('trg_order_slot'), [('  PROCEDURE book (p_outlet NUMBER, p_slot DATE) IS', '  END;')], gap='')))
add(code(trigger('trg_menu_stock_watch')))
add(para('**Proof.** {fig:trg1} calls `place_order` once and prints the values before and after: the token and pickup code (trg_order_token), the slot booking (trg_order_slot), the line priced from the menu with stock reduced (trg_order_item_stock) and the PLACED row in the audit log. {fig:trg2} shows trg_wallet_guard stopping a direct UPDATE, a slot of capacity 1 refusing a second order, loyalty points credited at pickup, the average rating updated and the full status trail. {fig:trg3} lists all nine triggers as ENABLED and shows the stock and price triggers firing on plain UPDATE statements.'))
add(figure('trg1', 'd13_trigger_order.png', 'Triggers fired by a single place_order call (before and after values)', width=6.0, max_h=6.8))
add(figure('trg2', 'd14_trigger_more.png', 'trg_wallet_guard, trg_order_slot (capacity), trg_loyalty_points, trg_review_rating and trg_order_status_audit', width=6.0, max_h=8.4))
add(figure('trg3', 'd07_triggers.png', 'All triggers ENABLED; stock-watch and price-audit triggers firing on direct UPDATE statements', width=5.0, max_h=8.2))

add(h2('4.5 Cursors'))
add(para('A cursor is needed wherever a query returns several rows that must be processed one at a time, or handed to the application. Every kind covered in the course is used:'))
add(table_caption('4.4', 'Cursors in the project'))
add(table(['Cursor type', 'Where', 'Purpose'], [
    ['Explicit, parameterised (OPEN / FETCH / CLOSE with %NOTFOUND, %ROWCOUNT, %ISOPEN)', 'c_cart in place_order', 'Reads the JSON cart line by line and inserts order items; %ROWCOUNT detects an empty cart'],
    ['Explicit (OPEN / FETCH / CLOSE)', 'c_outlets in generate_daily_summary', 'One summary row per outlet, written with MERGE'],
    ['Cursor FOR loop', 'c_queue in estimate_wait_minutes; c_lines in do_cancel', 'Adds up cooking time of the queue; restores stock line by line on cancel'],
    ['Implicit (SQL%ROWCOUNT, SQL%FOUND)', 'trg_order_slot', 'Detects that the slot-booking UPDATE matched no row (slot full)'],
    ['REF CURSOR (SYS_REFCURSOR)', 'get_low_stock, get_top_items, get_sales_report', 'Return result sets to Node.js, which reads them with getRows()'],
], [3200, 2600, 3226], size=19))
add(code(excerpt(member('PROCEDURE', 'generate_daily_summary'), [
    ('    CURSOR c_outlets IS', 'FROM outlet ORDER BY outlet_id;'),
    ('    OPEN c_outlets;', 'EXIT WHEN c_outlets%NOTFOUND;'),
    ('    END LOOP;\n    o_rows := c_outlets%ROWCOUNT;', 'CLOSE c_outlets;')])))
add(para('**Proof.** {fig:cur1} is a stand-alone block that exercises each cursor type and prints its attributes: a parameterised cursor `c_menu(2, 60)` with %ISOPEN, %ROWCOUNT per row and %NOTFOUND ending the loop; a cursor FOR loop over outlets; SQL%FOUND and SQL%ROWCOUNT after an UPDATE; and the REF CURSOR returned by `get_low_stock`. {fig:cur2} runs the explicit-cursor daily summary and fetches the best-seller REF CURSOR.'))
add(figure('cur1', 'd15_cursors.png', 'Explicit (parameterised), FOR-loop, implicit and REF cursors with their attributes', width=6.0, max_h=8.4))
add(figure('cur2', 'd09_cursors.png', 'Explicit cursor in generate_daily_summary and the REF CURSOR from get_top_items', width=5.6, max_h=6.6))

add(h2('4.6 Exception Handling'))
add(para('Every business rule raises a numbered error with RAISE_APPLICATION_ERROR. The API passes the message to the screen unchanged, so the same rule produces the same explanation in SQL*Plus and in the app (Section 5.1.6).'))
add(table(['Code', 'Meaning', 'Code', 'Meaning'], [
    ['-20001', 'User not found or deactivated', '-20009', 'Review not allowed or duplicate'],
    ['-20002', 'Outlet paused by the vendor', '-20010', 'Insufficient wallet balance'],
    ['-20003', 'Empty cart', '-20011', 'Invalid pickup time'],
    ['-20004', 'Coupon invalid, expired or below minimum', '-20012', 'Wrong pickup code / QR not scanned'],
    ['-20005', 'Illegal status transition', '-20013', 'Pickup slot full'],
    ['-20006', 'Too late to cancel', '-20020 to -20023', 'Dish missing, wrong outlet, unavailable, out of stock'],
    ['-20007', 'Invalid top-up amount', '-20008', 'Not authorised for this outlet or order'],
], [1300, 3213, 1300, 3213], size=19))
add(figure('err', 'd10_errors.png', 'Failure cases raising specific errors; each failed order was rolled back completely', width=6.0))

# ======================= 5. FRONT-END =======================
add(h1('5. FRONT-END (OPTIONAL – FOR HIGHER MARKS)'))
add(para('The front-end is a mobile-first single-page web app that works in any phone browser and can be added to the home screen like a native app. Vendors use the same app on a laptop at the counter. Instead of isolated screenshots, this chapter follows seven real walkthroughs. After each one, a SQL*Plus screenshot shows the exact rows that changed in Oracle, so every screen is backed by proof that the front-end and the database are integrated. All screenshots come from one recorded session against the live database.'))
add(h2('5.1 User Interface'))

add(h3('5.1.1 Sign up and wallet top-up'))
add(para('A new student registers, lands on an empty wallet and adds ₹500. The password is stored only as a salted hash, and the top-up goes through `topup_wallet`, which writes a TOPUP row to the ledger.'))
add(figure_row('j1', ['j/j1a_register.png', 'j/j1b_new_wallet.png', 'j/j1c_topup_done.png'], 'Registration, the new empty wallet, and the wallet after a ₹500 top-up',
               labels=['(a) Register', '(b) New wallet', '(c) After top-up']))
add(figure('p1', 'j/p1_signup.png', 'Database proof: the new APP_USER row (hashed password) and its TOPUP transaction', width=5.6, max_h=3.3))

add(h3('5.1.2 Browsing and placing an order'))
add(para('Siddharth opens the app, picks Main Food Court, checks a dish, then orders one Masala Dosa and two Pav Bhaji with WELCOME20 and a chosen pickup slot. The checkout shows live slot availability from `get_slots`. Paying calls `place_order` and returns a token and a QR code.'))
add(figure_row('j2a', ['j/j2a_home.png', 'j/j2b_menu.png', 'j/j2c_dish_sheet.png'], 'Home feed with offers and popular dishes, the outlet menu, and the dish detail sheet',
               labels=['(a) Home', '(b) Outlet menu', '(c) Dish detail']))
add(figure_row('j2b', ['j/j2d_checkout_slots.png', 'j/j2e_checkout_bill.png', 'j/j2f_ticket_qr.png'], 'Checkout with pickup slots and coupon, the bill, and the order ticket with token and pickup QR',
               labels=['(a) Slots and coupon', '(b) Bill', '(c) Token and QR']))
add(figure_row('p2', ['j/p2a_before_order.png', 'j/p2b_after_order.png'], 'Database proof before and after paying: order row with token, pickup code and amounts; two order lines priced from the menu; stock reduced (59 → 58, 60 → 58); slot booked; wallet debited (₹795.80 → ₹606.80)',
               width=[2.4, 3.6], max_h=[3.2, 7.4], labels=['(a) Before', '(b) After']))
FIGS['p2b'] = FIGS['p2']

add(h3('5.1.3 Vendor fulfilment and QR pickup'))
add(para('The order appears on the Food Court vendor board. The vendor accepts it, starts cooking and marks it ready; the student\'s phone switches to "Ready for pickup" and beeps. At the counter the vendor scans the QR (or types the code). A wrong code is refused by `verify_pickup`; the right one releases the order. The student can then rate the dishes.'))
add(figure('j3a', 'j/j3a_board_new_crop.png', 'Vendor board: the new order (token 4) arrives in "New orders" with the kitchen note and pickup time', width=6.2, max_h=3.6))
add(figure('j3b', 'j/j3b_board_cooking_crop.png', 'After Accept and Start cooking, the order moves to the "Cooking" lane', width=6.2, max_h=3.6))
add(figure_row('j3c', ['j/j3c_student_ready.png', 'j/j3d_wrong_code_crop.png', 'j/j3e_handed_over_crop.png', 'j/j3f_picked_up_rated.png'],
               'Student sees READY; vendor enters a wrong code (rejected) and then the right code (handed over); student rates the dish',
               width=1.5, max_h=3.2, labels=['(a) Ready', '(b) Wrong code', '(c) Handed over', '(d) Rated']))
add(figure('p3', 'j/p3_fulfilment.png', 'Database proof: five audit rows from PLACED to PICKED_UP, pickup time, loyalty points (413 → 431) and the new review with the updated average rating', width=5.4, max_h=5.4))

add(h3('5.1.4 Cancellation and refund'))
add(para('A second order (two Cold Coffees, ₹168) is cancelled by the student while it is still PLACED. `cancel_order` refunds the full amount, puts the stock back and frees the pickup-slot place.'))
add(figure_row('j4', ['j/j4a_cancel_button.png', 'j/j4b_cancelled.png', 'j/j4c_refund_in_wallet.png'], 'Cancel button on a placed order, the cancelled ticket, and the refund at the top of the wallet ledger',
               labels=['(a) Cancel', '(b) Cancelled', '(c) Refund']))
add(figure_row('p4', ['j/p4a_before_cancel.png', 'j/p4b_after_cancel.png'], 'Database proof before and after cancelling: status CANCELLED, DEBIT and REFUND rows, stock restored (54 → 56) and slot bookings reduced (3 → 2)',
               width=[2.7, 3.3], max_h=[3.8, 7.0], labels=['(a) Before', '(b) After']))
FIGS['p4b'] = FIGS['p4']

add(h3('5.1.5 Triggers seen through the interface'))
add(para('The vendor edits three rows on the menu page: Poha stock to 3, Gulab Jamun stock to 0 and Samosa price from ₹30 to ₹35. These are plain UPDATEs from the API; the triggers do the rest. The student menu immediately shows "Only 3 left" and "Sold out", and the reports page shows the new stock alerts and price change.'))
add(figure('j5a', 'j/j5a_vendor_edits_crop.png', 'Vendor menu and stock page after the edits (Poha stock 3 highlighted)', width=5.0, max_h=3.6))
add(figure_row('j5b', ['j/j5b_student_low_stock.png', 'j/j5c_student_sold_out.png', 'j/j5d_reports_alerts_crop.png'], 'Student menu showing "Only 3 left" and "Sold out", and the vendor report with the trigger-raised stock alerts',
               width=[1.9, 1.9, 2.3], max_h=4.0, labels=['(a) Low stock', '(b) Sold out', '(c) Stock alerts']))
add(figure('p5', 'j/p5_ui_triggers.png', 'Database proof: is_available set to N at stock 0, stock alerts raised for both dishes, and the price change recorded', width=5.6, max_h=4.4))

add(h3('5.1.6 Business rules enforced by the database'))
add(para('These six screens were produced by changing the database after the student had already opened the checkout page, so the screen was out of date when Pay was pressed. In each case the app sent the request and the database refused it with its own error message: stock reduced to 1, the chosen slot filled up, the wallet emptied, the outlet paused, and the vendor accepting the order a moment before the student pressed Cancel. This shows the rules are enforced by Oracle, not just hidden by the interface.'))
add(figure_row('j6a', ['j/j6a_expired_coupon.png', 'j/j6b_out_of_stock.png', 'j/j6c_slot_full.png'], 'Expired coupon (ORA-20004), stock ran out (ORA-20023) and slot filled up (ORA-20013)',
               width=2.0, max_h=2.2, labels=['(a) Expired coupon', '(b) Out of stock', '(c) Slot full']))
add(figure_row('j6b', ['j/j6d_low_balance.png', 'j/j6e_outlet_paused.png', 'j/j6f_cancel_too_late.png'], 'Insufficient balance (ORA-20010), outlet paused (ORA-20002) and cancel after acceptance (ORA-20006)',
               width=2.0, max_h=2.2, labels=['(d) Low balance', '(e) Outlet paused', '(f) Too late to cancel']))

add(h3('5.1.7 Reports and administration'))
add(figure('j7a', 'j/j7a_reports.png', 'Reports page after "Generate today\'s summary": best sellers and low stock from REF CURSOR procedures, and the summary row for today written by the explicit-cursor procedure', width=6.0, max_h=4.4))
add(figure('j7b', 'j/j7b_admin.png', 'Admin overview of all outlets and users, including the newly registered student', width=6.0, max_h=4.4))

add(h2('5.2 Integration with the DBMS'))
add(para('The system follows a three-tier architecture ({fig:arch}). The browser never connects to Oracle; it sends JSON requests to a small Node.js server built with Express, which checks the session and calls the matching PL/SQL unit through node-oracledb. Oracle does the work, and the result or error comes back the same way.'))
add(figure('arch', 'g02_architecture.png', 'Three-tier architecture of CampusBite', width=3.6, max_h=5.0))
add(para('**Connection.** node-oracledb runs in Thin mode (pure JavaScript, no Oracle Client needed). The server creates a connection pool on first use, and each request borrows a connection instead of opening a new one. Every call uses bind variables, and the user id always comes from the signed session cookie, never from the request body. The route behind "Pay & Place order":'))
add(code(between(src('server/routes/student.js'), "r.post('/orders',", '  res.json(out);\n}));')))
add(para('**Errors.** The server turns any ORA-20000 to ORA-20999 error into an HTTP 400 response that carries only the message, which the app shows as a red notification (Section 5.1.6). Unexpected errors are logged on the server and never shown to users.'))
add(table_caption('5.1', 'How front-end actions reach the database'))
add(table(['User action', 'API endpoint', 'Database unit called', 'Triggers that fire'], [
    ['Open an outlet', 'GET /api/outlets/:id/menu', 'v_menu, outlet_is_open, estimate_wait_minutes, next_available_slot', '–'],
    ['See pickup slots', 'GET /api/outlets/:id/slots', 'TABLE(get_slots(...))', '–'],
    ['Apply a coupon', 'POST /api/coupons/check', 'calc_coupon_discount', '–'],
    ['Pay & place order', 'POST /api/orders', 'place_order', 'token, slot, item_stock, stock_watch, status_audit, wallet_guard'],
    ['Add money', 'POST /api/wallet/topup', 'topup_wallet', 'wallet_guard'],
    ['Accept / cook / ready / reject', 'POST /api/vendor/orders/:id/status', 'update_order_status', 'status_audit, slot, stock_watch'],
    ['Scan pickup QR', 'POST /api/vendor/pickup', 'verify_pickup', 'status_audit, loyalty_points'],
    ['Cancel (student)', 'POST /api/orders/:id/cancel', 'cancel_order', 'slot, stock_watch, status_audit'],
    ['Rate a dish', 'POST /api/orders/:id/review', 'add_review', 'review_rating'],
    ['Edit price / stock', 'PATCH /api/vendor/menu/:id', 'UPDATE menu_item', 'price_audit, stock_watch'],
    ['Reports / summary', 'GET /api/vendor/reports, POST /api/vendor/summary', 'get_sales_report, get_top_items, get_low_stock, generate_daily_summary', '–'],
], [1900, 2300, 2600, 2226], size=18))
add(para('**Live updates and deployment.** The vendor board and the student\'s order page refresh every five seconds; the board beeps for new orders and the student\'s phone vibrates when the order is ready. The system runs locally (Oracle XE + `npm start`). The complete source code, SQL scripts and setup guide are in the project repository: ' + REPO_BLANK + '. The code is already prepared for free cloud hosting (`vercel.json`, `api/index.js`, cookie-based sessions), and a hosted link can be added to the repository later.'))

# ======================= 6. VERIFICATION =======================
add(h1('6. VERIFICATION & TESTING'))
add(para('Testing was done at two levels. `db/05_tests.sql` is a single PL/SQL block that creates its own test outlet, vendor and students, runs 53 checks, prints Expected / Actual / PASS or FAIL, and deletes its test data at the end. The front-end was tested through the walkthroughs in Chapter 5, including the negative cases in Section 5.1.6.'))
add(h2('6.1 Test Cases'))
INPUTS = json.loads((Path(__file__).parent / 'test_inputs.json').read_text(encoding='utf-8'))
PICK = ['TC01', 'TC02', 'TC03a', 'TC03c', 'TC03d', 'TC04a', 'TC04b', 'TC05', 'TC07', 'TC08a', 'TC09a', 'TC11', 'TC12', 'TC13a',
        'TC14a', 'TC15a', 'TC15b', 'TC16', 'TC18b', 'TC19', 'TC21', 'TC23', 'TC24', 'TC27', 'TC28', 'TC30', 'TC33', 'TC35', 'TC37']
allrows = {}
for line in (REPORT / 'd11_tests.txt').read_text(encoding='utf-8').replace('\r', '').split('\n'):
    m = re.match(r'^(TC\d+[a-z]?)\s+(.*?)\s{2,}(\S+(?: \S+)?)\s+(\S+(?: \S+)?)\s+(PASS|FAIL)\s*$', line.replace('\t', '    '))
    if m:
        tc, desc, exp, act, st = m.groups()
        allrows[tc] = [tc, desc, INPUTS.get(tc, ''), exp, act, 'Pass' if st == 'PASS' else 'Fail']
total_pass = sum(1 for r in allrows.values() if r[5] == 'Pass')
add(table_caption('6.1', f'Representative database test cases ({len(PICK)} of {len(allrows)}; all {total_pass} pass, see {{fig:t1}} and {{fig:t2}})'))
add(table(['TC ID', 'Description', 'Input', 'Expected Output', 'Actual Output', 'Status'], [allrows[t] for t in PICK],
          [800, 2600, 2326, 1250, 1250, 800], size=17, center_cols=(5,)))
add(table_caption('6.2', 'Front-end functional tests'))
add(table(['TC ID', 'Description', 'Input', 'Expected Output', 'Actual Output', 'Status'], [
    ['UT01', 'Register and top up', 'New student, +₹500', 'Account created; TOPUP row', 'Wallet ₹500 (Fig. {fig:j1}, {fig:p1})', 'Pass'],
    ['UT02', 'Place order with coupon and slot', '2 dishes, WELCOME20', 'Token and QR; stock, slot, wallet updated', 'Token 4, ₹189 (Fig. {fig:j2b}, {fig:p2})', 'Pass'],
    ['UT03', 'Vendor fulfilment', 'Accept, cook, ready', 'Board lanes and student status update', 'As expected (Fig. {fig:j3a}, {fig:j3b}, {fig:j3c})', 'Pass'],
    ['UT04', 'Wrong pickup code', '111111', 'Rejected', 'ORA-20012 shown (Fig. {fig:j3c}b)', 'Pass'],
    ['UT05', 'Correct pickup code and rating', 'Code from QR, 5 stars', 'Picked up; points and rating updated', '413 → 431 points (Fig. {fig:p3})', 'Pass'],
    ['UT06', 'Cancel and refund', 'Cancel PLACED order', 'Refund, stock back, slot freed', 'As expected (Fig. {fig:j4}, {fig:p4})', 'Pass'],
    ['UT07', 'Stock and price edits', 'Stock 3 / 0, price 35', 'Low-stock badge, sold out, alert, history', 'As expected (Fig. {fig:j5b}, {fig:p5})', 'Pass'],
    ['UT08', 'Expired coupon', 'FEST50', 'Error, no discount', 'ORA-20004 (Fig. {fig:j6a}a)', 'Pass'],
    ['UT09', 'Stock ran out before paying', 'Stock set to 1, qty 2', 'Order refused, nothing saved', 'ORA-20023 (Fig. {fig:j6a}b)', 'Pass'],
    ['UT10', 'Slot filled before paying', 'Slot capacity reached', 'Order refused', 'ORA-20013 (Fig. {fig:j6a}c)', 'Pass'],
    ['UT11', 'Wallet emptied before paying', 'Balance ₹10', 'Order refused', 'ORA-20010 (Fig. {fig:j6b}d)', 'Pass'],
    ['UT12', 'Outlet paused / cancel too late', 'Pause; accept before cancel', 'Both refused', 'ORA-20002, ORA-20006 (Fig. {fig:j6b}e, f)', 'Pass'],
], [700, 1900, 1650, 2000, 2076, 700], size=17, center_cols=(5,)))
add(h2('6.2 Output Screenshots'))
add(figure('t1', 'd11_tests_part1.png', 'Test run output, TC01 to TC24', width=6.0, max_h=8.4))
add(figure('t2', 'd12_tests_part2.png', 'Test run output, TC25 to TC37: 53 checks, 53 passed, 0 failed', width=6.0))
add(h2('6.3 Validation of Functionality'))
for t in [
    '**Constraints.** Negative amounts, invalid statuses and off-grid pickup times are rejected (TC02, TC36); composite keys and UNIQUE constraints stop duplicate reviews (TC14b).',
    '**Triggers.** Tokens increase per outlet per day (TC03b, TC17); stock is deducted and restored (TC03c, TC15b); sold-out dishes hide and return (TC18a–c); prices are recorded (TC19); every status change is logged (TC13b); slot bookings are counted and released (TC32–TC35). The same effects are visible in the app (Section 5.1.5).',
    '**Procedures and transactions.** GST and coupon arithmetic is exact (TC03a, TC08, TC10); refunds are complete (TC15a); a failed order leaves no trace (TC04a–c).',
    '**Authorisation.** A vendor cannot touch another outlet\'s orders (TC12); a student cannot cancel after acceptance (TC16, UT12); an order cannot be released without its QR code, with a wrong code, or twice (TC27, TC28, TC30).',
    '**Cursors.** The explicit cursor produces a summary row per outlet (TC23); the REF CURSOR returns the right rows (TC24); the parameterised cart cursor rejects an empty cart (TC20).',
    '**Front-end.** All twelve application tests passed, and the error messages in the app are the database\'s own (Section 5.1.6), so the rules are enforced in one place.',
]:
    add(bullet(t))
add(h2('6.4 Requirement Coverage'))
add(table_caption('6.3', 'Guideline requirements and where they are met'))
add(table(['Requirement (from the guidelines)', 'Where in this report', 'Evidence'], [
    ['Cover, certificate, abstract (150–200 words), table of contents', 'Front matter', 'Abstract: 196 words; TOC generated by Word'],
    ['Introduction: problem, objectives, importance of DBMS', 'Chapter 1', 'Sections 1.1–1.4'],
    ['System requirements', 'Chapter 2', 'Tables in 2.1, 2.2'],
    ['ER diagram, schema with constraints, normalisation', 'Chapter 3', 'Fig. {fig:chen}–{fig:cf2}; Tables 3.3–3.9; Section 3.4'],
    ['Functions with explanation, code and output', 'Section 4.1', 'Fig. {fig:func}'],
    ['Procedures with explanation, code and output', 'Section 4.2', 'Fig. {fig:proc}, {fig:life}'],
    ['Packages: specification, body, usage', 'Section 4.3', 'Fig. {fig:pkg}'],
    ['Triggers: event, level, rule, output', 'Section 4.4', 'Fig. {fig:trg1}, {fig:trg2}, {fig:trg3}; {fig:p5}'],
    ['Cursors: implicit, explicit, parameterised, with output', 'Section 4.5', 'Fig. {fig:cur1}, {fig:cur2}'],
    ['Front-end integrated with the database (9 marks)', 'Chapter 5', 'Seven walkthroughs, each with a database proof'],
    ['Mobile-based application (10 marks)', 'Chapter 5', 'Phone screenshots; installable web app (PWA)'],
    ['Test cases with output screenshots', 'Chapter 6', 'Tables 6.1, 6.2; Fig. {fig:t1}, {fig:t2}'],
    ['Results, conclusion, references (IEEE), appendices', 'Chapters 7–10', '–'],
    ['Figures numbered and captioned; own execution', 'Throughout', 'All screenshots from my own runs'],
], [3600, 1800, 3626], size=18))

# ======================= 7. RESULTS =======================
add(h1('7. RESULTS & DISCUSSION'))
add(h2('7.1 Achievements'))
for t in [
    'A 15-table schema in BCNF with 71 named constraints, 28 indexes, 2 views and 2 object types, all VALID.',
    'One package with nine functions and ten procedures carrying all business logic, including a pipelined table function and three REF CURSOR procedures.',
    'Nine triggers that keep tokens, stock, slots, audit data, ratings and loyalty points correct automatically, even for manual SQL changes.',
    'Atomic ordering: 53 of 53 database tests pass, including the rollback tests, and 12 of 12 front-end tests pass.',
    'A complete mobile-first front-end for three roles, with QR-based pickup and live order tracking, connected to the database through a REST API.',
    'A one-command rebuild (`db\\run.ps1 install.sql`) that recreates the database and a realistic week of data in seconds.',
]:
    add(bullet(t))
add(h2('7.2 Challenges Faced'))
for t in [
    '**Mutating-table problem for tokens.** Solved with a separate `token_counter` table updated by MERGE, which also gives a natural lock under concurrency.',
    '**Passing a whole cart to one procedure.** Passing the cart as JSON and reading it with JSON_TABLE inside an explicit cursor kept `place_order` to a single atomic call.',
    '**Reserved words as bind variables.** The vendor screens first failed with ORA-01745 because a bind variable was named `:uid` (UID is an Oracle pseudo-column). Renaming the binds fixed it.',
    '**Dates and time zones.** The driver converted DATE values using the server\'s time zone. I now fetch dates as campus wall-clock strings and convert the chosen slot with TO_DATE inside the PL/SQL call.',
    '**Making pickup secure.** The first version let any vendor click mark an order as collected. The secret pickup code and `verify_pickup` closed that gap.',
    '**Rush-hour overbooking.** The pickup-slot table with a CHECK on `booked <= capacity` and a conditional UPDATE in a trigger solved it. Testing late at night showed that after closing the next free slot was the next morning, which I turned into a pre-order feature.',
    '**The first interface was too plain.** My first prototype worked but looked generic (Appendix B). I redesigned it without changing any database code, which showed the value of keeping the rules in the database.',
]:
    add(bullet(t))
add(h2('7.3 Possible Improvements'))
for t in [
    '**Security:** separate Oracle roles for the application (EXECUTE on the package only) and Virtual Private Database policies so a vendor session can only see its own outlet.',
    '**Performance:** a function-based index on TRUNC(placed_at) and monthly partitioning of `orders` as data grows.',
    '**Automation:** DBMS_SCHEDULER jobs to auto-cancel unaccepted orders and to build the daily summary at midnight.',
    '**Payments and notifications:** a real UPI gateway and push notifications when the app is closed.',
]:
    add(bullet(t))

# ======================= 8. CONCLUSION =======================
add(h1('8. CONCLUSION'))
add(h2('8.1 Summary of Learning Outcomes'))
add(para('Building CampusBite end to end taught me far more than isolated lab queries. I learned to derive a schema from functional dependencies and to defend each normalisation decision, including the few places where storing a derived value is the right call. Writing the package showed how much cleaner an application becomes when every rule sits in one place: the Node.js server ended up as little more than a translator between JSON and PL/SQL calls. Triggers taught me to think about who else might change the data, and the mutating-table problem forced me to understand row-level trigger restrictions properly. I now understand when each kind of cursor fits, why savepoints and row locks matter in a multi-user system, and how to turn database errors into messages a user can act on. Writing tests that deliberately try to break the rules, and watching them fail for the right reason, was the most convincing proof that the design works.'))
add(h2('8.2 Future Scope'))
add(para('The next step is deploying the system for real users, with the database on Oracle Autonomous Database (Always Free) and the web app on Vercel, both of which the code already supports. The same database could serve a native Android app unchanged, since all the logic is in PL/SQL. With a semester of real orders, the reports could grow into demand forecasting (how many plates of biryani to prepare for Monday lunch) using analytic functions, which would reduce food waste. Multi-campus support and university ID-card login are other natural extensions.'))

# ======================= 9. REFERENCES =======================
add(h1('9. REFERENCES'))
for r in [
    '[1] A. Silberschatz, H. F. Korth, and S. Sudarshan, Database System Concepts, 7th ed. New York, NY, USA: McGraw-Hill, 2019.',
    '[2] R. Elmasri and S. B. Navathe, Fundamentals of Database Systems, 7th ed. Boston, MA, USA: Pearson, 2016.',
    '[3] S. Feuerstein and B. Pribyl, Oracle PL/SQL Programming, 6th ed. Sebastopol, CA, USA: O’Reilly Media, 2014.',
    '[4] Oracle Corporation, “Oracle Database PL/SQL Language Reference, 21c,” Oracle Help Center. [Online]. Available: https://docs.oracle.com/en/database/oracle/oracle-database/21/lnpls/ (accessed Oct. 24, 2026).',
    '[5] Oracle Corporation, “Oracle Database SQL Language Reference, 21c,” Oracle Help Center. [Online]. Available: https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/ (accessed Oct. 24, 2026).',
    '[6] Oracle Corporation, “Oracle Database JSON Developer’s Guide, 21c,” Oracle Help Center. [Online]. Available: https://docs.oracle.com/en/database/oracle/oracle-database/21/adjsn/ (accessed Oct. 24, 2026).',
    '[7] Oracle Corporation, “node-oracledb Documentation,” [Online]. Available: https://node-oracledb.readthedocs.io/ (accessed Oct. 24, 2026).',
    '[8] OpenJS Foundation, “Express 4.x API Reference,” [Online]. Available: https://expressjs.com/en/4x/api.html (accessed Oct. 24, 2026).',
    '[9] Graphviz Authors, “Graphviz – Graph Visualization Software,” [Online]. Available: https://graphviz.org/ (accessed Oct. 24, 2026).',
    '[10] M. Basaran, “html5-qrcode: A cross-platform HTML5 QR code reader,” GitHub. [Online]. Available: https://github.com/mebjas/html5-qrcode (accessed Oct. 24, 2026).',
    '[11] Unsplash, “Unsplash License,” [Online]. Available: https://unsplash.com/license (accessed Oct. 24, 2026). (Food photographs in the demo menu.)',
]:
    add(para(r, align='both'))

# ======================= 10. APPENDICES =======================
add(h1('10. APPENDICES', chap='A'))
add(h2('Appendix A – Additional Code', chap='A'))
add(para('The main database code is explained in Chapters 3 and 4. This appendix contains the supporting code that builds, tests and connects the system. The complete source of every file is in the project repository: ' + REPO_BLANK + '.'))
add(table_caption('A.1', 'Project files'))
add(table(['Path', 'Contents'], [
    ['db/01_schema.sql', '15 tables, constraints, indexes, object types'],
    ['db/02_triggers.sql', 'The 9 triggers'],
    ['db/03_package.sql', 'canteen_pkg specification and body; views v_menu and v_order_details'],
    ['db/04_seed.sql', 'Demo data generated through the package (a week of orders)'],
    ['db/05_tests.sql', 'The 53 automated test cases'],
    ['db/install.sql, db/run.ps1', 'One-command rebuild'],
    ['db/report/*.sql', 'The SQL*Plus demonstrations used for the screenshots in this report'],
    ['server/', 'Node.js + Express API (app.js, db.js, auth.js, routes/)'],
    ['public/', 'Front-end (index.html, app.js, styles.css, sw.js, manifest)'],
    ['api/index.js, vercel.json', 'Configuration for serverless hosting'],
], [3200, 5826], size=19, mono_cols=(0,)))
add(h3('One-step build script (db/install.sql)'))
add(code(src('db/install.sql')))
add(h3('Runner that reads credentials from .env (db/run.ps1)'))
add(code(src('db/run.ps1')))
add(h3('Test harness (excerpt from db/05_tests.sql)'))
tests = src('db/05_tests.sql')
add(code(excerpt(tests, [('  PROCEDURE result (', '  END;'), ('  -- TC04 insufficient balance', "result('TC04c', 'Stock unchanged after failed order', '48', TO_CHAR(v_n));")])))
add(h3('Demo-data generator (excerpt from db/04_seed.sql)'))
seed = src('db/04_seed.sql')
add(code(excerpt(seed, [('  FOR d IN REVERSE 1 .. 7 LOOP', "canteen_pkg.place_order(v_student, v_outlet, v_cart, v_coupon, NULL, NULL, v_order, v_token, v_total);"),
                         ('      IF DBMS_RANDOM.VALUE < 0.08 THEN', '      END IF;')])))
add(h3('Database helper on the server (excerpt from server/db.js)'))
dbjs = src('server/db.js')
add(code(excerpt(dbjs, [('// Calls a PL/SQL block;', '}\n\n// Business-rule'), ('function toHttpError(err) {', '  return null;\n}')], gap='')))
add(h3('Front-end request helper (excerpt from public/app.js)'))
add(code(between(src('public/app.js'), 'async function api(path, opts = {}) {', "  return data;\n}")))

add(h2('Appendix B – Additional Screenshots', chap='B'))
add(figure_row('v1', ['v1_login.jpg', 'v1_home.jpg', 'v1_order.jpg'], 'First working prototype (iteration 1): same database and API with a plain interface, later redesigned into the version in Chapter 5',
               width=1.9, max_h=4.0))
add(figure_row('dark', ['j/j8_home_dark.png', 'j/j2c_dish_sheet.png'], 'Dark theme and the dish detail sheet on a phone', width=2.2, max_h=4.4))
add(figure('lifecycle', 'g03_order_lifecycle.png', 'Order life-cycle enforced by is_valid_transition and verify_pickup', width=6.2))
add(figure('desc', 'd03_orders_desc.png', 'Structure and named constraints of the ORDERS table in Oracle', width=5.4, max_h=6.6))
add(figure('rows', 'd02_tables.png', 'Row counts of all 15 tables after loading the demo data', width=4.2, max_h=5.0))

BODY_XML = ''.join(B)
def _figref(m):
    before = BODY_XML[max(0, m.start() - 8):m.start()]
    plain = any(before.endswith(s) for s in ('Fig. ', 'Figure ', ', ', '–', 'and ', 'Figs. '))
    return FIGS[m.group(1)] if plain else 'Figure ' + FIGS[m.group(1)]


BODY_XML = re.sub(r'\{fig:(\w+)\}', _figref, BODY_XML)
# "Figure X" placed directly in text (not "Fig.") reads better at sentence start
BODY_XML = BODY_XML.replace('>Figure Figure', '>Figure')

# --------------------------------------------------------------------------
# Front matter: edit the template's own paragraphs
# --------------------------------------------------------------------------
with zipfile.ZipFile(TEMPLATE) as z:
    files = {n: z.read(n) for n in z.namelist()}
doc = files['word/document.xml'].decode('utf-8')

doc = doc.replace('&lt;Project Title&gt;</w:t></w:r></w:p>', escape(TITLE) + '</w:t></w:r></w:p>', 1)
tbl_start = doc.index('<w:tbl>')
tbl_end = doc.index('</w:tbl>', tbl_start)
tbl = doc[tbl_start:tbl_end]
for extra in re.findall(r'<w:tr>.*?</w:tr>|<w:tr .*?</w:tr>', tbl, re.S)[2:]:
    tbl = tbl.replace(extra, '', 1)
doc = doc[:tbl_start] + tbl + doc[tbl_end:]


def drop_para_containing(xml, needle):
    i = xml.index(needle)
    s = xml.rindex('<w:p>', 0, i)
    e = xml.index('</w:p>', i) + len('</w:p>')
    return xml[:s] + xml[e:]


def replace_para_containing(xml, needle, new_xml):
    i = xml.index(needle)
    s = xml.rindex('<w:p>', 0, i)
    e = xml.index('</w:p>', i) + len('</w:p>')
    return xml[:s] + new_xml + xml[e:]


doc = drop_para_containing(doc, '(Maximum 4 members.')
doc = doc.replace('Date of Submission: ____ / ____ / 2026', 'Date of Submission: 24 / 10 / 2026')
doc = doc.replace('&lt;Project Title&gt;</w:t></w:r><w:r>', escape(TITLE) + '</w:t></w:r><w:r>', 1)
doc = doc.replace('&lt;Name 1 (Reg. No.)&gt;, &lt;Name 2 (Reg. No.)&gt;, &lt;Name 3 (Reg. No.)&gt;, &lt;Name 4 (Reg. No.)&gt;',
                  '______________________________ (Reg. No. ________________)')

abstract = ('Canteen queues on campus are worst in the short breaks between classes, when hundreds of students try to order, pay and collect food at the same counter. '
            'CampusBite is a pre-ordering system that moves this work out of the queue. Students browse the menus of every outlet on their phone, pay from a prepaid wallet, '
            'book a fifteen-minute pickup slot and collect the food by showing a QR code, while vendors get a live order board, stock control and sales reports. '
            'The system is built on Oracle Database 21c Express Edition. The data is held in fifteen relations normalised to BCNF, and all business rules are implemented in PL/SQL inside the database: '
            'a package of nine functions and ten procedures, nine triggers that manage tokens, stock, slot capacity, auditing and loyalty points, and explicit, parameterised and REF cursors '
            'for row-by-row processing and reporting. A mobile-first web front-end built with Node.js, Express and node-oracledb invokes these procedures through a REST API. '
            'Fifty-three automated PL/SQL test cases, together with front-end tests covering both valid and invalid operations, confirm that the constraints, triggers and procedures work as intended '
            'and that a failed order is always rolled back completely.')
doc = replace_para_containing(doc, 'Write 150–200 words', para(abstract))
doc = replace_para_containing(doc, 'Keywords:',
                              para(runs=run('Keywords: ', b=True) + run('Oracle PL/SQL, Triggers, Cursors, Normalization, Stored Procedures, Pre-ordering System'))
                              + para('', after=60)
                              + para(runs=run('Project repository (complete source code, SQL scripts and setup guide): ', b=True) + run(REPO_BLANK), align='left'))
doc = drop_para_containing(doc, '(Right-click here in Word')

s1 = doc.rindex('<w:p>', 0, doc.index('1. INTRODUCTION'))
sect = doc.rindex('<w:sectPr')
doc = doc[:s1] + BODY_XML + doc[sect:]
if 'xmlns:pic=' not in doc:
    doc = doc.replace('<w:document ', '<w:document xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" ', 1)
files['word/document.xml'] = doc.encode('utf-8')

rels = files['word/_rels/document.xml.rels'].decode('utf-8')
ctypes = files['[Content_Types].xml'].decode('utf-8')
for k, (zpath, data) in enumerate(IMAGES, start=1):
    files[zpath] = data
    rels = rels.replace('</Relationships>', f'<Relationship Id="rIdImg{k}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/{zpath.split("/")[-1]}"/></Relationships>')
for ext, mime in (('png', 'image/png'), ('jpg', 'image/jpeg')):
    if f'Extension="{ext}"' not in ctypes:
        ctypes = ctypes.replace('<Default ', f'<Default Extension="{ext}" ContentType="{mime}"/><Default ', 1)
files['word/_rels/document.xml.rels'] = rels.encode('utf-8')
files['[Content_Types].xml'] = ctypes.encode('utf-8')
if 'word/comments.xml' in files:
    c = files['word/comments.xml'].decode('utf-8')
    files['word/comments.xml'] = re.sub(r'<w:comment .*?</w:comment>', '', c, flags=re.S).encode('utf-8')
core = files['docProps/core.xml'].decode('utf-8')
files['docProps/core.xml'] = re.sub(r'<dc:title>.*?</dc:title>', f'<dc:title>{escape(TITLE)}</dc:title>', core).encode('utf-8')

OUT.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
    for name in ['[Content_Types].xml'] + [n for n in files if n != '[Content_Types].xml']:
        z.writestr(name, files[name])
print('written', OUT, len(IMAGES), 'images,', len(FIGS), 'figures')
