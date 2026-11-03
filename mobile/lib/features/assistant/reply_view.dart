import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/tokens.dart';
import 'assistant_stream.dart';

/// The pieces an assistant's answer is written in: headings, paragraphs,
/// lists and tables, the subset of Markdown both assistants are told to use.
sealed class ReplyBlock {
  const ReplyBlock();
}

class HeadingBlock extends ReplyBlock {
  const HeadingBlock(this.level, this.text);
  final int level;
  final String text;
}

class ParagraphBlock extends ReplyBlock {
  const ParagraphBlock(this.text);
  final String text;
}

class ListBlock extends ReplyBlock {
  const ListBlock({required this.ordered, required this.items, this.start = 1});
  final bool ordered;
  final List<String> items;
  final int start;
}

class TableBlock extends ReplyBlock {
  const TableBlock(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;
}

final _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$');
final _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
final _numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');
final _tableSep = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');

/// Splits an answer into blocks. Forgiving: anything it does not recognise
/// is a paragraph, so no text is ever dropped.
List<ReplyBlock> parseReply(String text) {
  final blocks = <ReplyBlock>[];
  final para = <String>[];
  var inList = false;
  final items = <String>[];
  var listOrdered = false;
  var listStart = 1;

  void flushPara() {
    if (para.isNotEmpty) blocks.add(ParagraphBlock(para.join('\n')));
    para.clear();
  }

  void flushList() {
    if (items.isNotEmpty) blocks.add(ListBlock(ordered: listOrdered, items: List.of(items), start: listStart));
    items.clear();
    inList = false;
  }

  final lines = text.replaceAll('\r\n', '\n').split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      flushPara();
      flushList();
      continue;
    }
    final h = _heading.firstMatch(line);
    if (h != null) {
      flushPara();
      flushList();
      blocks.add(HeadingBlock(h.group(1)!.length, h.group(2)!.trim()));
      continue;
    }
    if (line.trimLeft().startsWith('|')) {
      flushPara();
      flushList();
      final rows = <List<String>>[];
      var j = i;
      for (; j < lines.length && lines[j].trimLeft().startsWith('|'); j++) {
        if (_tableSep.hasMatch(lines[j])) continue;
        rows.add(_cells(lines[j]));
      }
      i = j - 1;
      if (rows.isNotEmpty) blocks.add(TableBlock(rows.first, rows.skip(1).toList()));
      continue;
    }
    final b = _bullet.firstMatch(line);
    final n = b == null ? _numbered.firstMatch(line) : null;
    if (b != null || n != null) {
      flushPara();
      final ordered = n != null;
      if (items.isNotEmpty && listOrdered != ordered) flushList();
      if (items.isEmpty) {
        listOrdered = ordered;
        listStart = ordered ? int.parse(n.group(1)!) : 1;
      }
      items.add((b?.group(1) ?? n!.group(2)!).trim());
      inList = true;
      continue;
    }
    if (inList && items.isNotEmpty && line.startsWith(RegExp(r'\s{2,}'))) {
      // An indented line continues the item above it.
      items[items.length - 1] = '${items.last} ${line.trim()}';
      continue;
    }
    flushList();
    para.add(line);
  }
  flushPara();
  flushList();
  return blocks;
}

List<String> _cells(String row) {
  var r = row.trim();
  if (r.startsWith('|')) r = r.substring(1);
  if (r.endsWith('|')) r = r.substring(0, r.length - 1);
  return r.split('|').map((c) => c.trim()).toList();
}

/// True when most of [s]'s letters are Arabic: that text reads right to
/// left whatever the interface language.
bool isArabicText(String s) {
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(s).length;
  if (letters == 0) return false;
  final arabic = RegExp(r'[؀-ۿ]').allMatches(s).length;
  return arabic / letters > 0.3;
}

/// An answer, drawn from its text: headings, paragraphs, lists and tables,
/// with **bold**, numbered citation chips and links.
///
/// Links work only when they point somewhere the answer has a reason to send
/// people: [linkHosts] (this site, the answer's own sources and listings).
/// Anything else stays plain text, as on the website. [unverified] are
/// references the server could not match to a retrieved source; they are
/// marked where they appear. With [sections], every `##` heading starts a
/// section the reader can fold away (Ask a Lawyer's answers).
class ReplyView extends StatefulWidget {
  const ReplyView({
    super.key,
    required this.text,
    this.onCite,
    this.linkHosts = const {},
    this.unverified = const [],
    this.unverifiedLabel,
    this.sections = false,
  });

  final String text;
  final ValueChanged<int>? onCite;
  final Set<String> linkHosts;
  final List<String> unverified;
  final String? unverifiedLabel;
  final bool sections;

  @override
  State<ReplyView> createState() => _ReplyViewState();
}

class _ReplyViewState extends State<ReplyView> {
  final _recognizers = <GestureRecognizer>[];
  final _folded = <int>{};

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final blocks = parseReply(widget.text);
    final children = <Widget>[];
    if (!widget.sections) {
      for (final b in blocks) {
        if (children.isNotEmpty) children.add(const SizedBox(height: Space.sm));
        children.add(_block(context, b));
      }
    } else {
      // Sections: whatever comes before the first heading, then one foldable
      // group per heading.
      var index = -1;
      final groups = <(HeadingBlock?, List<ReplyBlock>)>[];
      for (final b in blocks) {
        if (b is HeadingBlock && b.level <= 3) {
          groups.add((b, []));
          index = groups.length - 1;
        } else {
          if (index < 0) {
            groups.add((null, []));
            index = 0;
          }
          groups[index].$2.add(b);
        }
      }
      for (var g = 0; g < groups.length; g++) {
        final (heading, body) = groups[g];
        final folded = _folded.contains(g);
        if (heading != null) {
          children.add(
            _SectionHeader(
              text: heading.text,
              open: !folded,
              first: g == 0,
              onTap: () => setState(() => folded ? _folded.remove(g) : _folded.add(g)),
            ),
          );
        }
        if (!folded) {
          for (final b in body) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: _block(context, b),
              ),
            );
          }
        }
      }
    }
    return SelectionArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _block(BuildContext context, ReplyBlock b) {
    final base = context.text.bodyLarge!.copyWith(height: 1.5);
    switch (b) {
      case HeadingBlock():
        final style = (b.level <= 2 ? context.text.titleMedium : context.text.titleSmall)!.copyWith(
          fontWeight: FontWeight.w700,
        );
        return _rich(context, b.text, style);
      case ParagraphBlock():
        return _rich(context, b.text, base);
      case ListBlock():
        final rtl = isArabicText(b.items.join(' '));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < b.items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xxs),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: b.ordered ? 26 : 18,
                        child: Text(
                          b.ordered ? '${b.start + i}.' : '•',
                          style: base.copyWith(color: context.colors.inkMuted),
                        ),
                      ),
                      Expanded(child: _rich(context, b.items[i], base)),
                    ],
                  ),
                ),
              ),
          ],
        );
      case TableBlock():
        return _table(context, b, base);
    }
  }

  Widget _table(BuildContext context, TableBlock t, TextStyle base) {
    final c = context.colors;
    final cols = [t.header.length, ...t.rows.map((r) => r.length)].reduce((a, b) => a > b ? a : b);
    final small = base.copyWith(fontSize: 14, height: 1.4);
    Widget cell(String s, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: _rich(context, s, head ? small.copyWith(fontWeight: FontWeight.w700) : small),
      ),
    );
    List<Widget> pad(List<String> row, {bool head = false}) => [
      for (var i = 0; i < cols; i++) cell(i < row.length ? row[i] : '', head: head),
    ];
    return Directionality(
      textDirection: isArabicText(t.header.join(' ') + t.rows.map((r) => r.join(' ')).join(' '))
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(horizontalInside: BorderSide(color: c.border)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: c.surfaceMuted),
                children: pad(t.header, head: true),
              ),
              for (final r in t.rows) TableRow(children: pad(r)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rich(BuildContext context, String text, TextStyle style) {
    return Text.rich(
      TextSpan(children: _inline(context, text, style)),
      textDirection: isArabicText(text) ? TextDirection.rtl : TextDirection.ltr,
    );
  }

  static final _token = RegExp(
    '$citeOpen([\\d,]+)$citeClose|\\*\\*(.+?)\\*\\*|\\[([^\\]]+)\\]\\((https?://[^)\\s]+)\\)|`([^`]+)`',
  );

  List<InlineSpan> _inline(BuildContext context, String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in _token.allMatches(text)) {
      if (m.start > at) spans.addAll(_plain(context, text.substring(at, m.start), style));
      if (m.group(1) != null) {
        spans.add(_cite(context, m.group(1)!, style));
      } else if (m.group(2) != null) {
        spans.addAll(_inline(context, m.group(2)!, style.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.group(3) != null) {
        spans.add(_link(context, m.group(3)!, m.group(4)!, style));
      } else if (m.group(5) != null) {
        spans.add(
          TextSpan(
            text: m.group(5),
            style: style.copyWith(fontFamily: 'monospace', backgroundColor: context.colors.surfaceMuted),
          ),
        );
      }
      at = m.end;
    }
    if (at < text.length) spans.addAll(_plain(context, text.substring(at), style));
    return spans;
  }

  /// Plain text, with any unverified reference in it marked.
  List<InlineSpan> _plain(BuildContext context, String text, TextStyle style) {
    final refs = widget.unverified.where((r) => r.trim().length >= 2).toList();
    if (refs.isEmpty) return [TextSpan(text: text, style: style)];
    final c = context.colors;
    final spans = <InlineSpan>[];
    var at = 0;
    while (at < text.length) {
      var best = -1;
      var bestRef = '';
      for (final r in refs) {
        final i = text.indexOf(r, at);
        if (i >= 0 && (best < 0 || i < best)) {
          best = i;
          bestRef = r;
        }
      }
      if (best < 0) {
        spans.add(TextSpan(text: text.substring(at), style: style));
        break;
      }
      if (best > at) spans.add(TextSpan(text: text.substring(at, best), style: style));
      spans.add(
        TextSpan(
          text: bestRef,
          semanticsLabel: widget.unverifiedLabel == null ? null : '$bestRef (${widget.unverifiedLabel})',
          style: style.copyWith(
            backgroundColor: c.danger.withValues(alpha: 0.08),
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dashed,
            decorationColor: c.danger,
          ),
        ),
      );
      at = best + bestRef.length;
    }
    return spans;
  }

  InlineSpan _cite(BuildContext context, String raw, TextStyle style) {
    final c = context.colors;
    final numbers = raw.split(',').map(int.tryParse).whereType<int>().toList();
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 3),
        child: Wrap(
          spacing: 3,
          children: [
            for (final n in numbers)
              Semantics(
                button: widget.onCite != null,
                label: '$n',
                child: GestureDetector(
                  onTap: widget.onCite == null ? null : () => widget.onCite!(n),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: c.emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    // Sized to its number: an unbounded alignment would
                    // stretch the badge across the whole line.
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        '$n',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.forest),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InlineSpan _link(BuildContext context, String label, String url, TextStyle style) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.replaceFirst(RegExp(r'^www\.'), '') ?? '';
    final allowed =
        uri != null && uri.scheme == 'https' && widget.linkHosts.any((h) => host == h || host.endsWith('.$h'));
    if (!allowed) return TextSpan(text: label, style: style);
    final r = TapGestureRecognizer()..onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication);
    _recognizers.add(r);
    return TextSpan(
      text: label,
      recognizer: r,
      style: style.copyWith(
        color: context.colors.emerald,
        decoration: TextDecoration.underline,
        decorationColor: context.colors.emerald,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text, required this.open, required this.first, required this.onTap});
  final String text;
  final bool open;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          decoration: BoxDecoration(
            border: first ? null : Border(top: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  textDirection: isArabicText(text) ? TextDirection.rtl : TextDirection.ltr,
                  style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: Motion.of(context, Motion.fast),
                child: Icon(Icons.expand_more_rounded, color: c.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
