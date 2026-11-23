import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/municipios.dart';
import '../utils/regioes.dart';

/// Lista de distribuidoras em caixas por região do país. Cada caixa abre e fecha,
/// tem "Marcar todas / Limpar" e a busca no topo filtra todas de uma vez.
class DistribuidoraRegioes extends StatefulWidget {
  const DistribuidoraRegioes({super.key, required this.app, required this.colorOf});
  final AppState app;
  final Color Function(String) colorOf;

  @override
  State<DistribuidoraRegioes> createState() => _DistribuidoraRegioesState();
}

class _DistribuidoraRegioesState extends State<DistribuidoraRegioes> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    // a região vem do estado onde a distribuidora atua: precisa da lista de municípios
    Municipios.carregar().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final q = _query.trim().toLowerCase();
    final visiveis = [for (final d in app.distribuidoras) if (q.isEmpty || d.toLowerCase().contains(q)) d];
    final grupos = agruparPorRegiao(visiveis, centros: app.centrosDistribuidoras);
    final total = app.selectedDistribuidoras.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18),
          hintText: 'Buscar distribuidora',
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text(total == 0 ? 'Nenhuma distribuidora marcada' : '$total marcada${total > 1 ? 's' : ''}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        if (total > 0) TextButton(onPressed: () => app.setDistribuidorasSelected(app.selectedDistribuidoras.toList(), false), child: const Text('Limpar tudo')),
      ]),
      if (grupos.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Nenhuma distribuidora encontrada.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
      for (final e in grupos.entries) _caixa(app, e.key, e.value, q.isNotEmpty),
    ]);
  }

  Widget _caixa(AppState app, Regiao regiao, List<String> nomes, bool buscando) {
    final marcadas = nomes.where(app.selectedDistribuidoras.contains).length;
    final aberta = buscando || marcadas > 0;
    final altura = (nomes.length * 40.0).clamp(40.0, 280.0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      // Material (e não só uma caixa colorida) para o efeito de toque dos itens aparecer sem erro.
      child: Material(
        color: AppColors.surfaceAlt,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: marcadas > 0 ? AppColors.primaryLight.withOpacity(0.6) : AppColors.divider),
        ),
        child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('${regiao.name}-$buscando-${marcadas > 0}'),
          initiallyExpanded: aberta,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          title: Text(regiao.nome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: Text('${nomes.length} distribuidora${nomes.length > 1 ? 's' : ''}${marcadas > 0 ? ' · $marcadas marcada${marcadas > 1 ? 's' : ''}' : ''}  ·  ${regiao.detalhe}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          children: [
            Row(children: [
              TextButton(onPressed: () => app.setDistribuidorasSelected(nomes, true), child: const Text('Marcar todas')),
              TextButton(onPressed: marcadas == 0 ? null : () => app.setDistribuidorasSelected(nomes, false), child: const Text('Limpar')),
            ]),
            SizedBox(
              height: altura,
              child: Scrollbar(
                child: ListView.builder(
                  itemCount: nomes.length,
                  itemExtent: 40,
                  itemBuilder: (_, i) {
                    final d = nomes[i];
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: app.selectedDistribuidoras.contains(d),
                      onChanged: (_) => app.toggleDistribuidoraSelection(d),
                      title: Row(children: [
                        Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: widget.colorOf(d), shape: BoxShape.circle)),
                        Expanded(child: Text(d, style: const TextStyle(fontSize: 13.5), overflow: TextOverflow.ellipsis)),
                      ]),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
