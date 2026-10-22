import 'package:material_ui/material_ui.dart';

import '../../app/theme/tokens.dart';
import '../utils/bidi.dart';

/// Text someone else wrote (an owner's title or description, an inquiry),
/// laid out in its own direction and aligned to its own start, and set in
/// its own script's face, whatever the interface language. Fills the width
/// it is given, so use it in a column.
class UserText extends StatelessWidget {
  const UserText(this.text, {super.key, this.style, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final ui = Directionality.of(context);
    final dir = directionOf(text, ui);
    final base = DefaultTextStyle.of(context).style.merge(style);
    return SizedBox(
      width: double.infinity,
      child: Text(
        text,
        textDirection: dir,
        textAlign: TextAlign.start,
        style: styleForScript(base, rtl: dir == TextDirection.rtl, multiline: maxLines != 1),
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
