import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Título de seção responsivo.
///
/// [actions] são botões do cabeçalho. Em tela larga ficam à direita do
/// título; em tela estreita descem para baixo do título (e quebram de
/// linha se precisar), então o título nunca é espremido.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> actions;

  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 520;

      final titleBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: narrow ? 18 : 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ],
      );

      final actionsBlock = actions.isEmpty
          ? null
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            );

      Widget body;
      if (narrow) {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleBlock,
            if (actionsBlock != null) ...[const SizedBox(height: 10), actionsBlock],
            if (trailing != null) ...[const SizedBox(height: 10), trailing!],
          ],
        );
      } else {
        body = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            if (actionsBlock != null) ...[const SizedBox(width: 12), Flexible(child: actionsBlock)],
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        );
      }

      return Padding(padding: const EdgeInsets.only(bottom: 14), child: body);
    });
  }
}
