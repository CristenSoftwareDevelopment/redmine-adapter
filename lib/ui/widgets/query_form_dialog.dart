import 'package:flutter/material.dart';

import '../../models/monitored_query.dart';

class QueryFormDialog extends StatefulWidget {
  const QueryFormDialog({
    super.key,
    this.initial,
  });

  final MonitoredQuery? initial;

  @override
  State<QueryFormDialog> createState() => _QueryFormDialogState();
}

class _QueryFormDialogState extends State<QueryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _queryUrl;
  late final TextEditingController _countPath;
  late final TextEditingController _pollSeconds;
  late final TextEditingController _customTitle;
  late final TextEditingController _customBody;
  bool _enabled = true;
  String _alertOn = alertOnAny;
  bool _showAdvanced = false;
  bool _showCustomTemplate = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    _name = TextEditingController(text: item?.name ?? '');
    _queryUrl = TextEditingController(
      text: item?.directUrl.isNotEmpty == true ? item!.directUrl : (item?.endpoint ?? ''),
    );
    _countPath = TextEditingController(text: item?.countPath ?? 'total_count');
    _pollSeconds = TextEditingController(
      text: item?.pollSeconds == null ? '' : '${item!.pollSeconds}',
    );
    _customTitle = TextEditingController(text: item?.notificationTitleTemplate ?? '');
    _customBody = TextEditingController(text: item?.notificationBodyTemplate ?? '');
    _enabled = item?.enabled ?? true;
    _alertOn = item?.alertOn ?? alertOnAny;
    _showCustomTemplate =
        (item?.notificationTitleTemplate?.isNotEmpty ?? false) ||
            (item?.notificationBodyTemplate?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _name.dispose();
    _queryUrl.dispose();
    _countPath.dispose();
    _pollSeconds.dispose();
    _customTitle.dispose();
    _customBody.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nova consulta' : 'Editar consulta'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Obrigatorio' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _queryUrl,
                  decoration: const InputDecoration(
                    labelText: 'URL da consulta no Redmine',
                    hintText: 'https://seu-redmine.com/projects/x/issues?query_id=123',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Obrigatorio';
                    final parsed = _parseUserUrl(value.trim());
                    if (parsed == null) {
                      return 'Informe uma URL valida (com /issues e query_id)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Cole a URL da pagina da consulta salva. O app gera o endpoint /issues.json automaticamente.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                    child: Text(
                      _showAdvanced ? 'Ocultar opcoes avancadas' : 'Mostrar opcoes avancadas',
                    ),
                  ),
                ),
                if (_showAdvanced)
                  TextFormField(
                    controller: _countPath,
                    decoration: const InputDecoration(
                      labelText: 'Caminho da contagem no JSON',
                      hintText: 'total_count',
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Obrigatorio' : null,
                  ),
                TextFormField(
                  controller: _pollSeconds,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Intervalo da consulta (segundos)',
                    hintText: 'vazio usa padrao global',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final parsed = int.tryParse(value);
                    if (parsed == null || parsed < 10) return 'Minimo 10 segundos';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _alertOn,
                  decoration: const InputDecoration(labelText: 'Notificar quando'),
                  items: const [
                    DropdownMenuItem(value: alertOnAny, child: Text('Qualquer mudanca')),
                    DropdownMenuItem(value: alertOnIncrease, child: Text('Somente aumento')),
                    DropdownMenuItem(value: alertOnDecrease, child: Text('Somente diminuicao')),
                  ],
                  onChanged: (value) => setState(() => _alertOn = value ?? alertOnAny),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                  title: const Text('Consulta ativa'),
                ),
                const Divider(),
                // Template personalizado por consulta
                InkWell(
                  onTap: () =>
                      setState(() => _showCustomTemplate = !_showCustomTemplate),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _showCustomTemplate
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        const Text('Template de notificacao personalizado (opcional)'),
                      ],
                    ),
                  ),
                ),
                if (_showCustomTemplate) ...[
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sobrescreve os templates globais apenas para esta consulta.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customTitle,
                    decoration: const InputDecoration(
                      labelText: 'Titulo personalizado',
                      hintText: 'Deixe vazio para usar o template global',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customBody,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Corpo personalizado',
                      hintText: 'Deixe vazio para usar o template global',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Chip(label: Text('{queryName}')),
                      Chip(label: Text('{previousCount}')),
                      Chip(label: Text('{currentCount}')),
                      Chip(label: Text('{diff}')),
                      Chip(label: Text('{newCount}')),
                      Chip(label: Text('{time}')),
                      Chip(label: Text('{url}')),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final resolved = _resolveUrls(_queryUrl.text.trim());
    if (resolved == null) return;

    final customTitleRaw = _customTitle.text.trim();
    final customBodyRaw = _customBody.text.trim();

    final result = MonitoredQuery(
      id: widget.initial?.id,
      name: _name.text.trim(),
      endpoint: resolved.endpoint,
      directUrl: resolved.directUrl,
      countPath: _countPath.text.trim(),
      pollSeconds:
          _pollSeconds.text.trim().isEmpty ? null : int.parse(_pollSeconds.text.trim()),
      enabled: _enabled,
      alertOn: _alertOn,
      lastCount: widget.initial?.lastCount,
      lastCheckedAt: widget.initial?.lastCheckedAt,
      notificationTitleTemplate: customTitleRaw.isEmpty ? null : customTitleRaw,
      notificationBodyTemplate: customBodyRaw.isEmpty ? null : customBodyRaw,
    );

    Navigator.of(context).pop(result);
  }

  Uri? _parseUserUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) return uri;
    if (!value.startsWith('/')) return null;
    return Uri.parse('https://placeholder.local$value');
  }

  _ResolvedUrls? _resolveUrls(String value) {
    final parsed = _parseUserUrl(value);
    if (parsed == null) return null;

    final isAbsolute = parsed.host != 'placeholder.local';
    final direct = _toPathAndQuery(parsed);
    final apiPath = _toJsonPath(parsed.path);
    final apiUri = parsed.replace(path: apiPath);
    final endpoint = isAbsolute ? apiUri.toString() : _toPathAndQuery(apiUri);

    return _ResolvedUrls(endpoint: endpoint, directUrl: isAbsolute ? value : direct);
  }

  String _toJsonPath(String path) {
    if (path.endsWith('.json')) return path;
    if (path.endsWith('/')) return '${path.substring(0, path.length - 1)}.json';
    return '$path.json';
  }

  String _toPathAndQuery(Uri uri) {
    final query = uri.query;
    return query.isEmpty ? uri.path : '${uri.path}?$query';
  }
}

class _ResolvedUrls {
  _ResolvedUrls({required this.endpoint, required this.directUrl});

  final String endpoint;
  final String directUrl;
}
