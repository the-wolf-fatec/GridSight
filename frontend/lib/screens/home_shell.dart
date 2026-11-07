import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import 'dashboard_screen.dart';
import 'import_screen.dart';
import 'parameters_screen.dart';
import 'map_screen.dart';
import 'indicators_screen.dart';
import 'comparison_screen.dart';

// (título completo, rótulo curto para a barra de baixo, ícone)
typedef _Dest = (String label, String shortLabel, IconData icon);

const _destinations = <_Dest>[
  ('Painel', 'Painel', Icons.dashboard_outlined),
  ('Importação de Dados', 'Importar', Icons.cloud_download_outlined),
  ('Parâmetros', 'Parâm.', Icons.tune),
  ('Mapa', 'Mapa', Icons.map_outlined),
  ('Indicadores', 'Indic.', Icons.insights_outlined),
  ('Comparar Cenários', 'Comparar', Icons.bar_chart_outlined),
];
const _mapIndex = 3;

List<Widget> _screens(int activeIndex) => [
      const DashboardScreen(),
      const ImportScreen(),
      const ParametersScreen(),
      MapScreen(active: activeIndex == _mapIndex),
      const IndicatorsScreen(),
      const ComparisonScreen(),
    ];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cts) {
      // Celular: barra embaixo. Tablet/desktop: menu lateral.
      if (Responsive.isPhone(cts.maxWidth)) return _mobileLayout(context, _index, _select);
      return _railLayout(context, _index, _select, cts.maxWidth >= Responsive.desktopMin);
    });
  }
}

// Celular: as 6 abas ficam visíveis, com rótulo curto (cabe sem quebrar).
Widget _mobileLayout(BuildContext context, int index, ValueChanged<int> onSelect) {
  return Scaffold(
    appBar: AppBar(
      toolbarHeight: 52,
      title: Text(_destinations[index].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
      actions: [
        IconButton(tooltip: 'Sair', icon: const Icon(Icons.logout, size: 20), onPressed: () => context.read<AppState>().logout()),
      ],
    ),
    body: IndexedStack(index: index, children: _screens(index)),
    bottomNavigationBar: NavigationBarTheme(
      data: NavigationBarThemeData(
        height: 64,
        labelPadding: EdgeInsets.zero,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            color: selected ? AppColors.energy : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.$3, size: 22),
              selectedIcon: Icon(d.$3, size: 22, color: AppColors.energy),
              label: d.$2,
              tooltip: d.$1,
            ),
        ],
      ),
    ),
  );
}

// Tablet / tela grande: menu lateral. Fica rolável quando a tela é baixa
// (ex.: tablet deitado), então nunca estoura a altura.
Widget _railLayout(BuildContext context, int index, ValueChanged<int> onSelect, bool extended) {
  return Scaffold(
    body: Row(children: [
      LayoutBuilder(builder: (context, constraint) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraint.maxHeight),
            child: IntrinsicHeight(
              child: NavigationRail(
                selectedIndex: index,
                onDestinationSelected: onSelect,
                extended: extended,
                minWidth: 72,
                minExtendedWidth: 210,
                backgroundColor: AppColors.surfaceAlt,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.energy, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.settings_input_antenna, color: AppColors.background)),
                    if (extended) ...[const SizedBox(height: 10), const Text('GridSight', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary))],
                  ]),
                ),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.$3),
                      selectedIcon: Icon(d.$3, color: AppColors.energy),
                      label: Text(d.$1),
                      padding: const EdgeInsets.symmetric(vertical: 2),
                    ),
                ],
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: IconButton(tooltip: 'Sair', icon: const Icon(Icons.logout, color: AppColors.textSecondary, size: 20), onPressed: () => context.read<AppState>().logout()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
      const VerticalDivider(width: 1),
      Expanded(child: IndexedStack(index: index, children: _screens(index))),
    ]),
  );
}
