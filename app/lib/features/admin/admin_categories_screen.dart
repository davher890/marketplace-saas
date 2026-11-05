import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/slug.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../repositories/admin_repository.dart';
import '../../repositories/catalog_repository.dart';
import '../../widgets/common.dart';

/// Category management: the storefront menu (main categories) and their
/// dropdowns (sub-categories). Two levels, ordered by position.
class AdminCategoriesScreen extends ConsumerWidget {
  const AdminCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(adminCategoriesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showCategoryDialog(context, ref, all: categories.value ?? const []),
        backgroundColor: AppColors.forest,
        foregroundColor: AppColors.cream,
        icon: const Icon(Icons.add),
        label: const Text('Nueva categoría'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminCategoriesProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text('Categorías', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 4),
            const Text(
              'Las categorías principales forman el menú de la tienda y las '
              'subcategorías, sus desplegables. Usa las flechas para cambiar '
              'el orden.',
            ),
            const SizedBox(height: 16),
            AsyncView(
              value: categories,
              onRetry: () => ref.invalidate(adminCategoriesProvider),
              builder: (all) {
                if (all.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No hay categorías.')),
                  );
                }
                final tree = CategoryNode.buildTree(all);
                return Column(
                  children: [
                    for (final (index, node) in tree.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CategoryCard(
                          node: node,
                          all: all,
                          isFirst: index == 0,
                          isLast: index == tree.length - 1,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Refreshes the admin list and the storefront menu after a change.
void _invalidateCategories(WidgetRef ref) {
  ref.invalidate(adminCategoriesProvider);
  ref.invalidate(categoriesProvider);
  ref.invalidate(categoryProductsProvider);
}

/// A main category with its sub-categories.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.node,
    required this.all,
    required this.isFirst,
    required this.isLast,
  });

  final CategoryNode node;
  final List<Category> all;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _CategoryRow(
            category: node.category,
            all: all,
            childCount: node.children.length,
            isFirst: isFirst,
            isLast: isLast,
          ),
          for (final (index, child) in node.children.indexed) ...[
            const Divider(height: 1, indent: 56),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: _CategoryRow(
                category: child,
                all: all,
                childCount: 0,
                isFirst: index == 0,
                isLast: index == node.children.length - 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _Action { edit, addChild, delete }

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({
    required this.category,
    required this.all,
    required this.childCount,
    required this.isFirst,
    required this.isLast,
  });

  final Category category;
  final List<Category> all;
  final int childCount;
  final bool isFirst;
  final bool isLast;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(AdminRepository repo) action,
  ) async {
    try {
      await action(ref.read(adminRepositoryProvider));
      _invalidateCategories(ref);
    } catch (error) {
      if (context.mounted) showMessage(context, describeError(error));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // The API refuses these too; explaining it here avoids a dead end.
    final blocker = category.productCount > 0
        ? 'Tiene ${_products(category.productCount)}. Muévelos a otra '
              'categoría o desactívala para ocultarla.'
        : childCount > 0
        ? 'Tiene subcategorías. Muévelas o elimínalas primero.'
        : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          blocker == null
              ? '¿Eliminar «${category.name}»?'
              : 'No se puede eliminar «${category.name}»',
        ),
        content: Text(blocker ?? 'Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(blocker == null ? 'Cancelar' : 'Entendido'),
          ),
          if (blocker == null)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, ref, (repo) => repo.deleteCategory(category.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = category.isActive
        ? null
        : AppColors.ink.withValues(alpha: 0.5);

    // A plain Row instead of a ListTile: ListTile gives `leading` a fixed
    // height, and on Android each arrow keeps a 48 px touch target, so two of
    // them overflowed. Here the row grows to fit them.
    return InkWell(
      onTap: () =>
          showCategoryDialog(context, ref, all: all, category: category),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MoveButton(
                  icon: Icons.keyboard_arrow_up,
                  tooltip: 'Subir',
                  onPressed: isFirst
                      ? null
                      : () => _run(
                          context,
                          ref,
                          (repo) => repo.moveCategory(category.id, up: true),
                        ),
                ),
                _MoveButton(
                  icon: Icons.keyboard_arrow_down,
                  tooltip: 'Bajar',
                  onPressed: isLast
                      ? null
                      : () => _run(
                          context,
                          ref,
                          (repo) => repo.moveCategory(category.id, up: false),
                        ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: muted,
                      fontWeight: category.isRoot ? FontWeight.w600 : null,
                    ),
                  ),
                  Text(
                    [
                      _products(category.productCount),
                      if (!category.isActive) 'Oculta',
                    ].join(' · '),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            Switch(
              value: category.isActive,
              onChanged: (value) => _run(
                context,
                ref,
                (repo) => repo.setCategoryActive(category.id, value),
              ),
            ),
            PopupMenuButton<_Action>(
              tooltip: 'Más acciones',
              onSelected: (action) => switch (action) {
                _Action.edit => showCategoryDialog(
                  context,
                  ref,
                  all: all,
                  category: category,
                ),
                _Action.addChild => showCategoryDialog(
                  context,
                  ref,
                  all: all,
                  parentId: category.id,
                ),
                _Action.delete => _delete(context, ref),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: _Action.edit, child: Text('Editar')),
                if (category.isRoot)
                  const PopupMenuItem(
                    value: _Action.addChild,
                    child: Text('Añadir subcategoría'),
                  ),
                const PopupMenuItem(
                  value: _Action.delete,
                  child: Text('Eliminar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _products(int count) => '$count producto${count == 1 ? '' : 's'}';

class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Same compact size on every platform (Android would otherwise pad
    // each button to 48x48).
    return IconButton(
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(40, 32),
        fixedSize: const Size(40, 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Opens the create / edit form. [parentId] preselects the parent of a new
/// sub-category.
Future<void> showCategoryDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<Category> all,
  Category? category,
  String? parentId,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _CategoryDialog(
      all: all,
      category: category,
      initialParentId: category?.parentId ?? parentId,
    ),
  );
  if (saved == true) {
    _invalidateCategories(ref);
    if (context.mounted) {
      showMessage(
        context,
        category == null ? 'Categoría creada.' : 'Categoría guardada.',
      );
    }
  }
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({
    required this.all,
    required this.category,
    required this.initialParentId,
  });

  final List<Category> all;
  final Category? category;
  final String? initialParentId;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.name);
  late final _slug = TextEditingController(text: widget.category?.slug);
  late final _description = TextEditingController(
    text: widget.category?.description,
  );
  late String? _parentId = widget.initialParentId;
  late bool _isActive = widget.category?.isActive ?? true;

  /// New categories get their slug from the name until it's edited by hand.
  late bool _slugEdited = widget.category != null;
  bool _saving = false;
  String? _error;

  bool get _hasChildren =>
      widget.category != null &&
      widget.all.any((c) => c.parentId == widget.category!.id);

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (!_slugEdited) _slug.text = slugify(_name.text);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .saveCategory(
            categoryId: widget.category?.id,
            name: _name.text.trim(),
            slug: _slug.text.trim(),
            parentId: _parentId,
            description: _description.text.trim(),
            isActive: _isActive,
          );
      if (mounted) Navigator.pop(context, true);
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
    // Only main categories can be parents (two levels), never itself.
    final parents = widget.all
        .where((c) => c.isRoot && c.id != widget.category?.id)
        .toList();

    return AlertDialog(
      title: Text(
        widget.category == null ? 'Nueva categoría' : 'Editar categoría',
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: widget.category == null,
                  decoration: const InputDecoration(labelText: 'Nombre *'),
                  maxLength: 80,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Escribe un nombre'
                      : null,
                ),
                TextFormField(
                  controller: _slug,
                  decoration: const InputDecoration(
                    labelText: 'URL (slug) *',
                    helperText: 'Se usa en /c/<slug>',
                  ),
                  onChanged: (_) => _slugEdited = true,
                  validator: (v) =>
                      RegExp(
                        r'^[a-z0-9]+(-[a-z0-9]+)*$',
                      ).hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Solo minúsculas, números y guiones',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _parentId,
                  decoration: InputDecoration(
                    labelText: 'Categoría padre',
                    helperText: _hasChildren
                        ? 'Tiene subcategorías, así que debe ser principal.'
                        : null,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Ninguna (categoría principal)'),
                    ),
                    for (final parent in parents)
                      DropdownMenuItem(
                        value: parent.id,
                        child: Text(parent.name),
                      ),
                  ],
                  onChanged: _hasChildren
                      ? null
                      : (value) => setState(() => _parentId = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    helperText: 'Se muestra bajo el título de la categoría',
                  ),
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1000,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Visible en la tienda'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
