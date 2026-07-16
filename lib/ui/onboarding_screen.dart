import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'home_screen.dart';
import '../services/theme_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();

  bool _loading = false;
  String? _errorMessage;

  // Rebuilt on every keystroke to show the live preview.
  String? get _normalizedPreview {
    final raw = _baseUrlController.text;
    if (raw.trim().isEmpty) return null;
    try {
      return _normalizeUrl(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _baseUrlController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  /// Normalizes whatever the user typed into a clean base URL:
  /// - trims whitespace
  /// - prepends https:// if no scheme is present
  /// - lowercases the scheme + host
  /// - strips trailing slashes
  /// - strips any path beyond the root (e.g. user pasted an issue URL)
  static String _normalizeUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) throw const FormatException('empty');

    // Prepend https:// when the user typed just a host or host/path.
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) throw const FormatException('invalid');

    // Keep only scheme + host (+ port if non-default).
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final port = uri.hasPort &&
            !((scheme == 'https' && uri.port == 443) ||
                (scheme == 'http' && uri.port == 80))
        ? ':${uri.port}'
        : '';

    return '$scheme://$host$port';
  }

  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Informe a URL do Redmine';
    }
    try {
      _normalizeUrl(value);
      return null;
    } on FormatException {
      return 'URL inválida. Exemplo: https://redmine.empresa.com';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final normalizedUrl = _normalizeUrl(_baseUrlController.text);
      await context.read<AppState>().saveOnboardingSettings(
            baseUrl: normalizedUrl,
            apiKey: _apiKeyController.text.trim(),
          );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final preview = _normalizedPreview;
    final rawInput = _baseUrlController.text.trim();
    final showPreview = preview != null && rawInput.isNotEmpty;
    final previewDiffers = showPreview && preview != rawInput;

    return Scaffold(
      backgroundColor: dark ? AppColors.darkSurface : AppColors.warmWhite,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Sp.s32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset('assets/icon.png', width: 52, height: 52),
                ),
                const SizedBox(height: Sp.s16),
                Text(
                  'Redmine Monitor',
                  textAlign: TextAlign.center,
                  style: AppText.subHeading(dark: dark),
                ),
                const SizedBox(height: Sp.s4),
                Text(
                  'Configure sua conexão para começar',
                  textAlign: TextAlign.center,
                  style: AppText.captionLight(dark: dark),
                ),
                const SizedBox(height: Sp.s32),
                if (appState.onboardingErrorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.s16, vertical: Sp.s12),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.08),
                      border: Border.all(
                          color: AppColors.orange.withValues(alpha: 0.35)),
                      borderRadius: BorderRadius.circular(AppRadius.standard),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.orange, size: 18),
                        const SizedBox(width: Sp.s8),
                        Expanded(
                          child: Text(
                            appState.invalidCredentials
                                ? 'Suas credenciais foram recusadas pelo Redmine. '
                                    'Verifique a URL e a API key e tente novamente.\n\n'
                                    '${appState.onboardingErrorMessage!}'
                                : appState.onboardingErrorMessage!,
                            style: AppText.caption(dark: dark).copyWith(
                              color: AppColors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Sp.s16),
                ],
                Container(
                  decoration: surfaceCard(dark: dark),
                  padding: const EdgeInsets.all(Sp.s24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'URL do Redmine',
                          style: AppText.caption(dark: dark).copyWith(
                            color: dark ? AppColors.warmGray300 : AppColors.warmGray500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Sp.s6),
                        TextFormField(
                          controller: _baseUrlController,
                          decoration: const InputDecoration(
                            hintText: 'redmine.empresa.com',
                            prefixIcon: Icon(
                              Icons.link_outlined,
                              size: 16,
                              color: AppColors.warmGray500,
                            ),
                          ),
                          keyboardType: TextInputType.url,
                          autofocus: true,
                          validator: _validateUrl,
                        ),
                        const SizedBox(height: Sp.s6),
                        Text(
                          'Cole qualquer URL do seu Redmine — o app detecta o endereço base automaticamente.',
                          style: AppText.microLabel(dark: dark),
                        ),
                        if (showPreview) ...[
                          const SizedBox(height: Sp.s8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: previewDiffers
                                ? _UrlPreviewChip(
                                    key: ValueKey(preview),
                                    url: preview,
                                    dark: dark,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                        const SizedBox(height: Sp.s16),
                        Text(
                          'API Key',
                          style: AppText.caption(dark: dark).copyWith(
                            color: dark ? AppColors.warmGray300 : AppColors.warmGray500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Sp.s6),
                        TextFormField(
                          controller: _apiKeyController,
                          decoration: const InputDecoration(
                            hintText: 'Chave de acesso da API REST',
                            prefixIcon: Icon(
                              Icons.key_outlined,
                              size: 16,
                              color: AppColors.warmGray500,
                            ),
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe a API Key';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: Sp.s6),
                        Text(
                          'Redmine → Minha conta → Chave de acesso API',
                          style: AppText.microLabel(dark: dark),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: Sp.s16),
                          _ErrorBanner(
                            message: _errorMessage!,
                            dark: dark,
                          ),
                        ],
                        const SizedBox(height: Sp.s24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.pureWhite,
                                    ),
                                  )
                                : const Text('Salvar e Continuar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UrlPreviewChip extends StatelessWidget {
  const _UrlPreviewChip({super.key, required this.url, required this.dark});

  final String url;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final textColor = dark ? AppColors.focusBlue : AppColors.badgeBlueText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.s12, vertical: Sp.s8),
      decoration: BoxDecoration(
        color: dark ? AppColors.badgeBlueBg.withValues(alpha: 0.1) : AppColors.badgeBlueBg,
        border: Border.all(color: AppColors.focusBlue.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AppRadius.micro),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high_outlined, size: 16, color: textColor),
          const SizedBox(width: Sp.s8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppText.microLabel(dark: dark).copyWith(color: textColor),
                children: [
                  const TextSpan(text: 'Será usado: '),
                  TextSpan(
                    text: url,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.dark});

  final String message;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.s12, vertical: Sp.s8),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.micro),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.orange, size: 16),
          const SizedBox(width: Sp.s8),
          Expanded(
            child: Text(
              message,
              style: AppText.microLabel(dark: dark).copyWith(
                color: AppColors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
