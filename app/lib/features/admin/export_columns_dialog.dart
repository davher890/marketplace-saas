import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/export_columns.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/common.dart';

/// Opens "Columnas del Excel": which columns the monthly orders file has and
/// in what order. Saved for the shop (every admin, every device).
Future<void> showExportColumnsDialog(BuildContext context) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => const ExportColumnsDialog(),
  );
  if (saved == true && context.mounted) {
    showMessage(context, 'Columnas guardadas');
  }
}

class ExportColumnsDialog extends ConsumerStatefulWidget {
  const ExportColumnsDialog({super.key});

  @override
  ConsumerState<ExportColumnsDialog> createState() =>
      _ExportColumnsDialogState();
}

class _ExportColumnsDialogState extends ConsumerState<ExportColumnsDialog> {
  late final Future<ExportColumns> _loading;

  @override
  void initState() {
    super.initState();
    _loading = ref.read(orderRepositoryProvider).fetchExportColumns().then((
      columns,
    ) {
      // setState so the buttons (outside the FutureBuilder) turn on too.
      if (mounted) {
        setState(() {
          _labels = {for (final c in columns.available) c.key: c.label};
          _default = [for (final c in columns.available) c.key];
          _show(columns.selected);
        });
      }
      return columns;
    });
  }

  Map<String, String> _labels = {};

  /// Every column in the default order.
  List<String> _default = [];

  /// Every column, the chosen ones first in their order, then the rest.
  List<String> _order = [];
  Set<String> _chosen = {};
  bool _saving = false;
  String? _error;

  void _show(List<String> selected) {
    _chosen = {...selected};
    _order = [
      ...selected,
      for (final key in _default)
        if (!_chosen.contains(key)) key,
    ];
  }

  void _reorder(int from, int to) =>
      setState(() => _order.insert(to, _order.removeAt(from)));

  Future<void> _save() async {
    final columns = [
      for (final key in _order)
        if (_chosen.contains(key)) key,
    ];
    if (columns.isEmpty) {
      setState(() => _error = 'Elige al menos una columna');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(orderRepositoryProvider).saveExportColumns(columns);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return AlertDialog(
      title: const Text('Columnas del Excel'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 420,
        height: (height * 0.6).clamp(240, 560),
        child: FutureBuilder<ExportColumns>(
          future: _loading,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(describeError(snapshot.error!)));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Marca las columnas que quieres en el archivo y '
                    'arrástralas para cambiar el orden.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.cocoa),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: _order.length,
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final key = _order[index];
                      final chosen = _chosen.contains(key);
                      return ListTile(
                        key: ValueKey(key),
                        dense: true,
                        leading: Checkbox(
                          value: chosen,
                          onChanged: (on) => setState(() {
                            on == true ? _chosen.add(key) : _chosen.remove(key);
                            _error = null;
                          }),
                        ),
                        title: Text(
                          _labels[key] ?? key,
                          style: chosen
                              ? null
                              : const TextStyle(color: AppColors.cocoa),
                        ),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Tooltip(
                            message: 'Arrastrar para mover',
                            child: const Icon(Icons.drag_handle),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving || _default.isEmpty
              ? null
              : () => setState(() {
                  _show(_default);
                  _error = null;
                }),
          child: const Text('Restablecer'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving || _default.isEmpty ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
