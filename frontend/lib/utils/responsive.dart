import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Ajudantes de layout responsivo (celular, tablet e tela grande).
///
/// Regras usadas no app inteiro:
///  - celular  : largura < 600
///  - tablet   : 600 a 1099 (menu lateral compacto)
///  - desktop  : >= 1100 (menu lateral com texto)
class Responsive {
  Responsive._();

  static const double phoneMax = 600;
  static const double desktopMin = 1100;

  static bool isPhone(double width) => width < phoneMax;

  /// Margem das telas: menor no celular, maior no tablet.
  static double pagePadding(double width) {
    if (width < 400) return 12;
    if (width < phoneMax) return 16;
    if (width < desktopMin) return 24;
    return 32;
  }
}

/// Corpo padrão de uma tela rolável.
///
/// - Respeita a área segura (entalhe, barra de navegação).
/// - Rola na vertical, então teclado ou texto grande nunca causam "overflow".
/// - Em tela larga, limita a largura do conteúdo e centraliza.
/// - [builder] recebe a largura real disponível para o conteúdo.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.builder, this.maxWidth = 1200});

  final Widget Function(BuildContext context, double contentWidth) builder;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(builder: (context, cts) {
        final pad = Responsive.pagePadding(cts.maxWidth);
        final contentWidth = math.min(cts.maxWidth - pad * 2, maxWidth);
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 8),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: builder(context, contentWidth),
            ),
          ),
        );
      }),
    );
  }
}

/// Grade de cartões com altura fixa (não depende de proporção, então não
/// fica gigante no celular nem espremida no tablet).
/// Colunas: 1 (muito estreito), 2 (celular/tablet) ou 4 (largo).
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.mainAxisExtent = 96, this.spacing = 12});

  final List<Widget> children;
  final double mainAxisExtent;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 860 ? 4 : (c.maxWidth >= 300 ? 2 : 1);
      return GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          mainAxisExtent: mainAxisExtent,
        ),
        children: children,
      );
    });
  }
}

/// Botão compacto para caber lado a lado no celular.
ButtonStyle compactOutlined() => OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      visualDensity: VisualDensity.compact,
    );
