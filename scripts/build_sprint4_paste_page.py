#!/usr/bin/env python3
"""Rebuild the copy-and-paste page docs/sprint4/sections-10-11.html.

The Section 10 text and the feature list are converted from their Markdown
sources and put into the page. Section 11 (with its embedded diagrams) is
kept exactly as it is in the existing page.

    /usr/bin/python3 scripts/build_sprint4_paste_page.py
"""
import html
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
DOCS = os.path.join(ROOT, 'docs', 'sprint4')
PAGE = os.path.join(DOCS, 'sections-10-11.html')
SECTIONS_MD = os.path.join(DOCS, '02-testing-architecture-sections-10-11.md')
FEATURES_MD = os.path.join(DOCS, '03-feature-status-and-sprint3-feedback.md')

NOTES = '''  <div class="notes">
    <h2>Before you paste (this box is not copied)</h2>
    <ul>
      <li><b>Feature list:</b> paste it where the brief asks for the list of features, and give its heading a Heading style so it appears in the table of contents. Then update the table of contents (right-click it → Update field → Update entire table).</li>
      <li><b>Section 10 is the short version.</b> Each test case is one table row. Initialization, Test Steps and Tear Down are stated once in 10.1.1 because they are the same for every case.</li>
      <li><b>10.1.7</b> is the source for the "Test cases:" line the brief asks for under each requirement in Section 5.</li>
      <li><b>10.1.1 lists the PINs of the demonstration accounts.</b> Leave that row out if the document will be shared outside the class.</li>
      <li><b>If a diagram does not appear after pasting</b>, insert it from <code>docs/sprint4/images/</code> (Insert → Image).</li>
      <li><b>To save paper:</b> the tables paste at 9 pt. Setting the page margins to Narrow before printing saves about one more page.</li>
    </ul>
  </div>
'''


def inline(text):
    text = html.escape(text, quote=False)
    text = text.replace('&lt;br&gt;', '<br>')
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', text)
    text = re.sub(r'(?<![*\w])\*([^*\s][^*]*)\*(?![*\w])', r'<i>\1</i>', text)
    return text


def cells(row):
    return [c.strip() for c in row.strip().strip('|').split('|')]


def heading(line, prefix):
    """'## 10.1 Test Cases' -> (tag, id, title, level class) based on the section number."""
    title = line.lstrip('#').strip()
    number = re.match(r'(\d+(?:\.\d+)*)', title)
    if not number:
        return 'h1', prefix + '-top', title
    parts = number[1].split('.')
    tag = 'h1' if len(parts) == 2 and parts[1] == '0' else 'h2' if len(parts) == 2 else 'h3'
    return tag, 's' + '-'.join(parts), title


def convert(markdown, prefix):
    """Tiny Markdown subset: headings, paragraphs, tables, fenced code, ordered and bullet lists."""
    out, nav, lines, i = [], [], markdown.split('\n'), 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.strip() == '---':
            i += 1
        elif line.startswith('#'):
            tag, anchor, title = heading(line, prefix)
            out.append(f'<{tag} id="{anchor}">{inline(title)}</{tag}>')
            nav.append((tag, anchor, title))
            i += 1
        elif line.startswith('|'):
            rows = []
            while i < len(lines) and lines[i].startswith('|'):
                rows.append(cells(lines[i]))
                i += 1
            head, body = rows[0], rows[2:]
            out.append('<table class="grid"><thead><tr>' + ''.join(f'<th>{inline(c)}</th>' for c in head) +
                       '</tr></thead><tbody>' +
                       ''.join('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in r) + '</tr>' for r in body) +
                       '</tbody></table>')
        elif line.startswith('```'):
            i += 1
            code = []
            while i < len(lines) and not lines[i].startswith('```'):
                code.append('<p class="codeline">' + (html.escape(lines[i], quote=False).replace(' ', '&nbsp;') or '&nbsp;') + '</p>')
                i += 1
            i += 1
            out.append('<table class="code"><tr><td>' + ''.join(code) + '</td></tr></table>')
        elif re.match(r'(\d+\.|-) ', line):
            ordered = line[0].isdigit()
            items = []
            while i < len(lines) and re.match(r'(\d+\.|-) ', lines[i]):
                items.append('<li>' + inline(re.sub(r'^(\d+\.|-) ', '', lines[i])) + '</li>')
                i += 1
            out.append(('<ol>' if ordered else '<ul>') + ''.join(items) + ('</ol>' if ordered else '</ul>'))
        else:
            paragraph = [line]
            i += 1
            while i < len(lines) and lines[i].strip() and not re.match(r'(#|\||```)', lines[i]):
                paragraph.append(lines[i])
                i += 1
            out.append('<p>' + inline(' '.join(paragraph)) + '</p>')
    return '\n'.join(out), nav


def nav_rows(nav):
    rows = []
    for tag, anchor, title in nav:
        level = {'h1': ('l1', 6), 'h2': ('l2', 2), 'h3': ('l3', 3)}[tag]
        label = re.match(r'[\d.]+', title)
        label = label[0] if label else title
        shown = title + (' (introduction)' if tag == 'h1' and label != title else '')
        rows.append(f'  <div class="navrow {level[0]}"><a href="#{anchor}">{html.escape(shown, quote=False)}</a>'
                    f'<button data-from="{anchor}" data-level="{level[1]}" data-label="{html.escape(label)}" '
                    f'aria-label="Copy {html.escape(label)}">Copy</button></div>')
    return '\n'.join(rows)


def between(text, start, end):
    a = text.index(start)
    return a, text.index(end, a)


def main():
    page = open(PAGE, encoding='utf-8').read()
    sections = open(SECTIONS_MD, encoding='utf-8').read()
    section10 = sections[sections.index('## 10.0 Testing'):sections.index('## 11.0 Architectural Modeling')]
    features = open(FEATURES_MD, encoding='utf-8').read()
    features = features[features.index('<!-- feature-list:start -->') + len('<!-- feature-list:start -->'):
                        features.index('<!-- feature-list:end -->')]

    body10, nav10 = convert(section10, 's10')
    body_features, nav_features = convert(features, 'features')

    # Section 11 sheet and its navigation group are kept as they are.
    a, b = between(page, '<div class="navgroup"><button class="all" data-all="sec11">', '</nav>')
    nav11 = page[a:b]
    a, b = between(page, '<div class="sheet"><div class="doc" id="sec11">', '</main>')
    sheet11 = page[a:b]

    nav = ('<nav aria-label="Copy sections">\n'
           '  <h1>Feature list, Sections 10 and 11</h1>\n'
           '  <p>Press a Copy button, click in the Sprint 4 document, and paste. Headings, tables and diagrams come across as they look here.</p>\n'
           '  <div class="navgroup"><button class="all" data-all="secfeatures">Copy the feature list</button>\n'
           + nav_rows(nav_features) + '\n  </div>\n'
           '  <div class="navgroup"><button class="all" data-all="sec10">Copy all of Section 10</button>\n'
           + nav_rows(nav10) + '\n  </div>\n  ' + nav11)
    main_html = ('<main>\n' + NOTES +
                 '  <div class="sheet"><div class="doc" id="secfeatures">\n' + body_features + '\n  </div></div>\n'
                 '  <div class="sheet"><div class="doc" id="sec10">\n' + body10 + '\n  </div></div>\n  ' + sheet11)

    a, _ = between(page, '<nav aria-label="Copy sections">', '</nav>')
    _, b = between(page, '<main>', '</main>')
    page = page[:a] + nav + '</nav>\n' + main_html + page[b:]
    page = re.sub(r'<title>.*?</title>', '<title>ServeSync Sprint 4 — feature list, Sections 10 and 11, ready to paste</title>', page)
    # 'Copy all' labels: "Section 10" for sec10/sec11, plain wording for the feature list.
    page = page.replace("copyRange(range, 'Section ' + b.dataset.all.slice(3));",
                        "copyRange(range, /^sec\\d/.test(b.dataset.all) ? 'Section ' + b.dataset.all.slice(3) : 'the feature list');")
    open(PAGE, 'w', encoding='utf-8').write(page)
    print(f'Wrote {PAGE}: feature list {len(body_features):,} chars, Section 10 {len(body10):,} chars.')


if __name__ == '__main__':
    main()
