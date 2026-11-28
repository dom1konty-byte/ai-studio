// Стиль Markdown: один для ответов директора и окна «Документы».
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';

final MarkdownStyleSheet rubkaMdStyle = MarkdownStyleSheet(
  p: Rubka.body(),
  h1: Rubka.head(22),
  h2: Rubka.head(19),
  h3: Rubka.head(16),
  code: Rubka.mono().copyWith(backgroundColor: Rubka.codeBg),
  codeblockDecoration: BoxDecoration(
      color: Rubka.codeBg, borderRadius: BorderRadius.circular(8)),
  codeblockPadding: const EdgeInsets.all(12),
  a: Rubka.body(color: Rubka.primary)
      .copyWith(decoration: TextDecoration.underline),
  listBullet: Rubka.body(),
);

/// То же, но шрифт 14 (компактный режим).
final MarkdownStyleSheet rubkaMdStyleCompact = rubkaMdStyle.copyWith(
  p: Rubka.body(size: 14),
  listBullet: Rubka.body(size: 14),
);
