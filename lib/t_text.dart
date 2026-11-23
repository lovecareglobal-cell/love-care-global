import 'package:flutter/material.dart';
import '../language_service.dart';

// NEW: No keys needed. Just put your English text:
//   TText('Book Nurse')  -> shows translated version automatically
//   TText('Welcome', style: TextStyle(fontSize: 20))
// Works on ALL pages, updates instantly when language changes.
class TText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  const TText(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.overflow});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LanguageService.instance,
      builder: (_, __) => Text(
        LanguageService.instance.tr(text),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

// For AppBar titles, button labels, etc. where you need a String not a Widget:
//   Text(LanguageService.instance.tr('Book Nurse'))  - but wrap page in ListenableBuilder
// Or use this helper inside a ListenableBuilder:
extension TrExt on String {
  String get tr => LanguageService.instance.tr(this);
}
