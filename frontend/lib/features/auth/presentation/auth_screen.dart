import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_theme.dart';

Future<bool> requireAccount(
  BuildContext context,
  WidgetRef ref, {
  required String action,
}) async {
  if (ref.read(sessionControllerProvider).isAuthenticated) return true;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AuthSheet(action: action),
  );
  return result ?? false;
}

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: _AuthPanel(action: 'sincronizar seus dados'),
            ),
          ),
        ),
      );
}

class _AuthSheet extends StatelessWidget {
  const _AuthSheet({required this.action});
  final String action;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
              ),
            ),
            _AuthPanel(action: action, closeOnSuccess: true),
          ]),
        ),
      );
}

class _AuthPanel extends ConsumerStatefulWidget {
  const _AuthPanel({required this.action, this.closeOnSuccess = false});
  final String action;
  final bool closeOnSuccess;

  @override
  ConsumerState<_AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends ConsumerState<_AuthPanel> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _register = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, (previous, next) {
      if (next.isAuthenticated && widget.closeOnSuccess && context.mounted) {
        Navigator.pop(context, true);
      }
    });
    final session = ref.watch(sessionControllerProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: .09),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.sync_rounded, color: AppTheme.accent),
              ),
              const SizedBox(height: 16),
              Text(
                _register ? 'Criar sua conta' : 'Entrar na sua conta',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Entre para ${widget.action}. O mercado continua disponível sem cadastro.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: _register
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (session.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      session.error!,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: session.isLoading ? null : _submit,
                  child: session.isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_register
                          ? 'Criar e continuar'
                          : 'Entrar e continuar'),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: session.isLoading
                    ? null
                    : () {
                        ref
                            .read(sessionControllerProvider.notifier)
                            .clearError();
                        setState(() => _register = !_register);
                      },
                child: Text(
                  _register ? 'Já tenho uma conta' : 'Criar uma conta',
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;
    final controller = ref.read(sessionControllerProvider.notifier);
    _register
        ? controller.register(email, password)
        : controller.login(email, password);
  }
}
