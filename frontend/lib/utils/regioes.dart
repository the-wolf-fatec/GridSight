import 'municipios.dart';

/// Região do país de cada distribuidora, para organizar a lista de importação em caixas.
///
/// A região sai do estado onde a distribuidora atua (centro dos ativos, calculado pelo backend); sem isso, pelo nome.
/// pequenas (nomes que começam com Cer, Coop, Coor...) ficam na caixa "Cooperativas e permissionárias",
/// e o que não for reconhecido cai em "Outras". Para classificar uma distribuidora nova,
/// basta acrescentar o nome (sem acento, em minúsculas) em [_porNome].
enum Regiao { norte, nordeste, centroOeste, sudeste, sul, cooperativas, outras }

extension RegiaoInfo on Regiao {
  String get nome => switch (this) {
        Regiao.norte => 'Norte',
        Regiao.nordeste => 'Nordeste',
        Regiao.centroOeste => 'Centro-Oeste',
        Regiao.sudeste => 'Sudeste',
        Regiao.sul => 'Sul',
        Regiao.cooperativas => 'Cooperativas e permissionárias',
        Regiao.outras => 'Outras',
      };

  String get detalhe => switch (this) {
        Regiao.norte => 'AC, AM, AP, PA, RO, RR, TO',
        Regiao.nordeste => 'AL, BA, CE, MA, PB, PE, PI, RN, SE',
        Regiao.centroOeste => 'DF, GO, MS, MT',
        Regiao.sudeste => 'ES, MG, RJ, SP',
        Regiao.sul => 'PR, RS, SC',
        Regiao.cooperativas => 'Região varia; pequenas distribuidoras locais',
        Regiao.outras => 'Sem região definida',
      };
}

String _norm(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().trim().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

const Map<String, Regiao> _porNome = {
  // Norte
  'amazonas energia': Regiao.norte,
  'roraima energia': Regiao.norte,
  'energisa ac': Regiao.norte,
  'energisa ro': Regiao.norte,
  'energisa to': Regiao.norte,
  'equatorial pa': Regiao.norte,
  'cea equatorial': Regiao.norte,
  // Nordeste
  'enel ce': Regiao.nordeste,
  'equatorial ma': Regiao.nordeste,
  'equatorial pi': Regiao.nordeste,
  'equatorial al': Regiao.nordeste,
  'neoenergia coelba': Regiao.nordeste,
  'neoenergia cosern': Regiao.nordeste,
  'neoenergia pernambuco': Regiao.nordeste,
  'energisa pb': Regiao.nordeste,
  'energisa borborema': Regiao.nordeste,
  'energisa se': Regiao.nordeste,
  'sulgipe': Regiao.nordeste,
  // Centro-Oeste
  'equatorial go': Regiao.centroOeste,
  'energisa mt': Regiao.centroOeste,
  'energisa ms': Regiao.centroOeste,
  'neoenergia brasilia': Regiao.centroOeste,
  'chesp': Regiao.centroOeste,
  // Sudeste
  'cemig d': Regiao.sudeste,
  'light': Regiao.sudeste,
  'enel rj': Regiao.sudeste,
  'edp es': Regiao.sudeste,
  'enel sao paulo': Regiao.sudeste,
  'edp sao paulo': Regiao.sudeste,
  'cpfl paulista': Regiao.sudeste,
  'cpfl piratininga': Regiao.sudeste,
  'cpfl leste paulista': Regiao.sudeste,
  'cpfl mococa': Regiao.sudeste,
  'cpfl santa cruz': Regiao.sudeste,
  'cpfl sul paulista': Regiao.sudeste,
  'neoenergia elektro': Regiao.sudeste,
  'energisa minas rio': Regiao.sudeste,
  'energisa nova friburgo': Regiao.sudeste,
  'energisa sul sudeste': Regiao.sudeste,
  'cnee': Regiao.sudeste,
  'edevp': Regiao.sudeste,
  'eeb': Regiao.sudeste,
  'dmed': Regiao.sudeste,
  // Sul
  'copel dis': Regiao.sul,
  'celesc dis': Regiao.sul,
  'rge': Regiao.sul,
  'ceee equatorial': Regiao.sul,
  'castro dis': Regiao.sul,
  'cocel': Regiao.sul,
  'forcel': Regiao.sul,
  'eflul': Regiao.sul,
  'hidropan': Regiao.sul,
  'demei': Regiao.sul,
  'eletrocar': Regiao.sul,
  'nova palma': Regiao.sul,
  'mux energia': Regiao.sul,
  'joao cesa': Regiao.sul,
};

/// Região pela sigla do estado.
Regiao? regiaoDaUf(String? uf) => switch (uf) {
      'AC' || 'AM' || 'AP' || 'PA' || 'RO' || 'RR' || 'TO' => Regiao.norte,
      'AL' || 'BA' || 'CE' || 'MA' || 'PB' || 'PE' || 'PI' || 'RN' || 'SE' => Regiao.nordeste,
      'DF' || 'GO' || 'MS' || 'MT' => Regiao.centroOeste,
      'ES' || 'MG' || 'RJ' || 'SP' => Regiao.sudeste,
      'PR' || 'RS' || 'SC' => Regiao.sul,
      _ => null,
    };

/// Região de uma distribuidora. Com o centro dos ativos dela ([centro] = [lat, lon]) a região vem
/// do estado onde ela realmente opera (vale para TODAS, inclusive cooperativas); sem ele, pelo nome.
Regiao regiaoDe(String nome, {List<double>? centro}) {
  if (centro != null && centro.length >= 2) {
    final r = regiaoDaUf(Municipios.ufMaisProxima(centro[0], centro[1]));
    if (r != null) return r;
  }
  final n = _norm(nome);
  final r = _porNome[n];
  if (r != null) return r;
  if (RegExp(r'^(cer|coop|coor|cooper)').hasMatch(n)) return Regiao.cooperativas;
  return Regiao.outras;
}

/// Agrupa os nomes por região, na ordem de exibição, cada grupo em ordem alfabética.
Map<Regiao, List<String>> agruparPorRegiao(Iterable<String> nomes, {Map<String, List<double>> centros = const {}}) {
  final out = <Regiao, List<String>>{for (final r in Regiao.values) r: <String>[]};
  for (final n in nomes) {
    out[regiaoDe(n, centro: centros[n])]!.add(n);
  }
  for (final l in out.values) {
    l.sort((a, b) => _norm(a).compareTo(_norm(b)));
  }
  out.removeWhere((_, l) => l.isEmpty);
  return out;
}
