import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true, _submitting = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit(AppState app) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    await Future.delayed(const Duration(milliseconds: 300));
    app.login(_user.text, _pass.text);
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final brand = Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(color: AppColors.energy, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: AppColors.energy.withOpacity(0.35), blurRadius: 24, spreadRadius: 2)]),
        child: const Icon(Icons.settings_input_antenna, color: AppColors.background, size: 48),
      ),
      const SizedBox(height: 20),
      const Text('GridSight', textAlign: TextAlign.center, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: 0.5)),
      const SizedBox(height: 10),
      const Text('Planejamento de cobertura de radiofrequência\npara redes de sensores em sistemas de distribuição de energia', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
    ]);

    final form = Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Entrar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Acesso restrito ao painel de planejamento.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _user,
              enabled: !_submitting,
              decoration: const InputDecoration(labelText: 'Usuário', prefixIcon: Icon(Icons.person_outline, size: 20)),
              textInputAction: TextInputAction.next,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o usuário' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pass,
              enabled: !_submitting,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Senha',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20), onPressed: () => setState(() => _obscure = !_obscure)),
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submitting ? null : _submit(app),
              validator: (v) => (v == null || v.isEmpty) ? 'Informe a senha' : null,
            ),
            if (app.loginError != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.alert.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.alert.withOpacity(0.4))),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.alert, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(app.loginError!, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary))),
                ]),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : () => _submit(app),
                child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background)) : const Text('Entrar'),
              ),
            ),
          ]),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(builder: (context, cts) {
                if (cts.maxWidth > 640) return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: brand), const SizedBox(width: 48), Expanded(child: form)]);
                return Column(mainAxisSize: MainAxisSize.min, children: [brand, const SizedBox(height: 36), form]);
              }),
            ),
          ),
        ),
      ),
    );
  }
}
