import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/money.dart';
import '../../core/slug.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/costs.dart';
import '../../models/product.dart';
import '../../repositories/admin_repository.dart';
import '../../repositories/product_image_repository.dart';
import '../../repositories/catalog_repository.dart';
import '../../widgets/common.dart';

/// Loads the product to edit (or starts a new one) and shows the form.
class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({super.key, this.productId});

  /// `null` when creating a new product.
  final String? productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(adminCategoriesProvider);
    if (productId == null) {
      return AsyncView(
        value: categories,
        builder: (cats) => _ProductForm(product: null, categories: cats),
      );
    }
    final product = ref.watch(adminProductProvider(productId!));
    return AsyncView(
      value: product,
      onRetry: () => ref.invalidate(adminProductProvider(productId!)),
      builder: (product) => AsyncView(
        value: categories,
        builder: (cats) => product == null
            ? const Center(child: Text('Producto no encontrado.'))
            // Re-created when variants change (e.g. after saving new ones) so the
            // form always holds the persisted variant ids; image changes keep it.
            : _ProductForm(
                key: ValueKey(
                  '${product.id}:${product.variants.map((v) => v.id).join(',')}',
                ),
                product: product,
                categories: cats,
              ),
      ),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({
    super.key,
    required this.product,
    required this.categories,
  });

  final Product? product;
  final List<Category> categories;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final Product? _p = widget.product;
  late final _name = TextEditingController(text: _p?.name ?? '');
  late final _slug = TextEditingController(text: _p?.slug ?? '');
  late final _description = TextEditingController(text: _p?.description ?? '');
  late final _price = TextEditingController(
    text: _p == null ? '' : centsToInput(_p.basePriceCents),
  );
  late final _customizationLabel = TextEditingController(
    text: _p?.customizationLabel ?? '',
  );

  /// What it costs the shop, who it's bought from and its box (admin only).
  late final _cost = TextEditingController(
    text: _p?.costCents == null ? '' : centsToInput(_p!.costCents!),
  );
  late String? _supplierId = _p?.supplierId;
  late BoxSize? _boxSize = _p?.boxSize;

  /// Options the variants combine, e.g. Tamaño (8 cm, 10 cm) and Material.
  late final List<_OptionControllers> _options = [
    for (final option in variantOptions(_p?.variants ?? const []))
      _OptionControllers(option, onChanged: _onOptionChanged),
  ];

  /// Categories the product is listed in; the first one is its main one.
  late final List<String> _categoryIds = [...?_p?.categoryIds];
  late bool _isActive = _p?.isActive ?? true;
  late bool _isFeatured = _p?.isFeatured ?? false;
  late bool _isCustomizable = _p?.isCustomizable ?? false;

  /// Every variant row created while editing, saved or not, so a value typed
  /// again gets its SKU and price back. Only [_variants] are saved.
  late final List<_VariantFields> _allVariants = [
    for (final v in _p?.variants ?? const <ProductVariant>[])
      _VariantFields(
        VariantDraft.fromVariant(v)
          ..options = Map.of(optionsOf(v, _p!.variants)),
      ),
  ];

  /// One row per combination of the options' values, in order.
  late List<_VariantFields> _variants = _arrangeVariants();

  /// Lists the customer picks one value from (no price or stock).
  late final List<_ChoiceFieldControllers> _choiceFields = [
    for (final field in _p?.choiceFields ?? const <ChoiceField>[])
      _ChoiceFieldControllers(field),
  ];
  bool _slugEdited = false;
  bool _saving = false;
  bool _duplicating = false;

  bool get _isNew => _p == null;

  @override
  void initState() {
    super.initState();
    _slugEdited = !_isNew;
    _name.addListener(() {
      if (!_slugEdited) _slug.text = slugify(_name.text);
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _slug,
      _description,
      _price,
      _cost,
      _customizationLabel,
    ]) {
      c.dispose();
    }
    for (final v in _allVariants) {
      v.dispose();
    }
    for (final option in _options) {
      option.dispose();
    }
    for (final field in _choiceFields) {
      field.dispose();
    }
    super.dispose();
  }

  /// Rows for the current options: existing variants are kept for their
  /// combination (see [matchCombinations]), new ones are added.
  List<_VariantFields> _arrangeVariants() {
    final options = [
      for (final o in _options)
        if (o.name.text.trim().isNotEmpty)
          (name: o.name.text.trim(), values: o.currentValues),
    ];
    final combinations = optionCombinations(options);
    if (combinations.isEmpty) combinations.add({});
    final matches = matchCombinations(combinations, [
      for (final row in _allVariants) row.draft.options,
    ]);
    return [
      for (final (i, combination) in combinations.indexed)
        switch (matches[i]) {
          final int j => _allVariants[j]..draft.options = combination,
          null => _newVariant(combination),
        },
    ];
  }

  _VariantFields _newVariant(Map<String, String> options) {
    final row = _VariantFields(VariantDraft(options: Map.of(options)));
    _allVariants.add(row);
    return row;
  }

  /// Renames carry the variants' SKU and price over to the new name.
  void _onOptionChanged(_OptionControllers option) {
    final name = option.name.text.trim();
    final values = option.currentValues;
    final rows = [for (final row in _allVariants) row.draft.options];
    if (name.isNotEmpty) {
      if (option.lastName.isNotEmpty && name != option.lastName) {
        for (final options in rows) {
          final value = options.remove(option.lastName);
          if (value != null) options[name] = value;
        }
      }
      // One value edited in place, e.g. "Mediano" → "Mediana".
      if (values.length == option.lastValues.length) {
        final changed = [
          for (var i = 0; i < values.length; i++)
            if (values[i] != option.lastValues[i]) i,
        ];
        if (changed.length == 1) {
          final i = changed.single;
          for (final options in rows) {
            if (options[name] == option.lastValues[i]) {
              options[name] = values[i];
            }
          }
        }
      }
      option.lastName = name;
    }
    option.lastValues = values;
    setState(() => _variants = _arrangeVariants());
  }

  void _addOption() => setState(
    () => _options.add(_OptionControllers(null, onChanged: _onOptionChanged)),
  );

  void _removeOption(int index) => setState(() {
    _options.removeAt(index).dispose();
    _variants = _arrangeVariants();
  });

  /// The product's store page. On the web it opens in a new tab, so the form
  /// stays open; in the app it goes on top of the form (back returns to it).
  void _viewInStore(String slug) {
    final path = '/product/${Uri.encodeComponent(slug)}';
    if (kIsWeb) {
      launchUrl(Uri.base.resolve(path), webOnlyWindowName: '_blank');
    } else {
      context.push(path);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_variants.length > maxVariants) {
      showMessage(
        context,
        'Son ${_variants.length} combinaciones; el máximo es $maxVariants. '
        'Quita algún valor.',
      );
      return;
    }
    setState(() => _saving = true);

    final drafts = [for (final v in _variants) v.toDraft()];
    final row = Product(
      id: _p?.id ?? '',
      categoryId: _categoryIds.firstOrNull,
      categoryIds: List.of(_categoryIds),
      name: _name.text.trim(),
      slug: _slug.text.trim(),
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      basePriceCents: parseCents(_price.text)!,
      isCustomizable: _isCustomizable,
      customizationLabel:
          _isCustomizable && _customizationLabel.text.trim().isNotEmpty
          ? _customizationLabel.text.trim()
          : null,
      choiceFields: [for (final field in _choiceFields) field.toField()],
      isActive: _isActive,
      isFeatured: _isFeatured,
      costCents: parseCents(_cost.text),
      supplierId: _supplierId,
      boxSize: _boxSize,
    ).toJson();

    try {
      final saved = await ref
          .read(adminRepositoryProvider)
          .saveProduct(productId: _p?.id, product: row, variants: drafts);
      final id = saved.id;
      _invalidateCatalog(id);
      if (!mounted) return;
      showMessage(context, 'Producto guardado');
      // New products continue in edit mode so images can be added.
      if (_isNew) context.go('/admin/products/$id');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _invalidateCatalog(String productId) {
    ref.invalidate(adminProductsProvider);
    ref.invalidate(adminProductProvider(productId));
    ref.invalidate(featuredProductsProvider);
    ref.invalidate(categoryProductsProvider);
    ref.invalidate(productBySlugProvider);
  }

  /// Makes a hidden copy of the saved product and opens it for editing.
  Future<void> _duplicate() async {
    setState(() => _duplicating = true);
    try {
      final copy = await ref
          .read(adminRepositoryProvider)
          .duplicateProduct(_p!.id);
      ref.invalidate(adminProductsProvider);
      if (!mounted) return;
      showMessage(
        context,
        'Copia creada: "${copy.name}". Está oculta hasta que la actives.',
      );
      context.go('/admin/products/${copy.id}');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _duplicating = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar "${_p!.name}"?'),
        content: const Text(
          'Se borrarán sus variantes e imágenes. Los pedidos existentes se conservan. '
          'Si solo quieres ocultarlo, desactívalo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminRepositoryProvider).deleteProduct(_p!.id);
      ref.invalidate(adminProductsProvider);
      if (mounted) context.go('/admin/products');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    }
  }

  /// Categories ordered as a tree: parents followed by their children,
  /// with sub-categories labelled "Parent › Child".
  List<(Category, String)> _categoryChoices() => [
    for (final node in CategoryNode.buildTree(widget.categories)) ...[
      (node.category, node.category.name),
      for (final child in node.children)
        (child, '${node.category.name} › ${child.name}'),
    ],
  ];

  void _toggleCategory(String id, bool selected) => setState(() {
    selected ? _categoryIds.add(id) : _categoryIds.remove(id);
  });

  void _makeMain(String? id) => setState(() {
    if (id == null) return;
    _categoryIds
      ..remove(id)
      ..insert(0, id);
  });

  Widget _categoriesField() {
    final choices = _categoryChoices();
    String label(String id) =>
        choices.where((c) => c.$1.id == id).firstOrNull?.$2 ?? '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Categorías',
            helperText:
                'Puedes elegir varias. Sin ninguna, no sale en el menú.',
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (category, name) in choices)
                FilterChip(
                  label: Text(name),
                  selected: _categoryIds.contains(category.id),
                  // Same look as the other chips: cream on dark green.
                  labelStyle: TextStyle(
                    color: _categoryIds.contains(category.id)
                        ? AppColors.cream
                        : AppColors.ink,
                  ),
                  checkmarkColor: AppColors.cream,
                  onSelected: (selected) =>
                      _toggleCategory(category.id, selected),
                ),
            ],
          ),
        ),
        if (_categoryIds.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(_categoryIds.join(',')),
            initialValue: _categoryIds.first,
            items: [
              for (final id in _categoryIds)
                DropdownMenuItem(value: id, child: Text(label(id))),
            ],
            onChanged: _makeMain,
            decoration: const InputDecoration(
              labelText: 'Categoría principal',
              helperText: 'La que se muestra en la lista de productos.',
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go('/admin/products'),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  _isNew ? 'Nuevo producto' : _p!.name,
                  style: textTheme.displaySmall,
                ),
              ),
              if (!_isNew)
                IconButton(
                  tooltip: 'Ver en la tienda',
                  onPressed: () => _viewInStore(_p!.slug),
                  icon: const Icon(Icons.open_in_new),
                ),
              if (!_isNew)
                IconButton(
                  tooltip: 'Duplicar',
                  onPressed: _duplicating ? null : _duplicate,
                  icon: _duplicating
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.content_copy_outlined),
                ),
              if (!_isNew)
                IconButton(
                  tooltip: 'Eliminar',
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Información',
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
              ),
              TextFormField(
                controller: _slug,
                decoration: const InputDecoration(
                  labelText: 'URL (slug) *',
                  helperText: 'Se usa en /product/<slug>',
                ),
                onChanged: (_) => _slugEdited = true,
                validator: (v) =>
                    RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(v ?? '')
                    ? null
                    : 'Solo minúsculas, números y guiones',
              ),
              const SizedBox(height: 8),
              _categoriesField(),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      decoration: const InputDecoration(
                        labelText: 'Precio (€) *',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) => parseCents(v ?? '') == null
                          ? 'Importe no válido'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _cost,
                      decoration: const InputDecoration(
                        labelText: 'Coste (€)',
                        helperText: 'Solo lo ves tú',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isNotEmpty && parseCents(v!) == null
                          ? 'Importe no válido'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _CostFields(
                supplierId: _supplierId,
                boxSize: _boxSize,
                onSupplier: (id) => setState(() => _supplierId = id),
                onBoxSize: (size) => setState(() => _boxSize = size),
              ),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 5,
              ),
              SwitchListTile(
                title: const Text('Visible en la tienda'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              SwitchListTile(
                title: const Text('Destacado en la portada'),
                value: _isFeatured,
                onChanged: (v) => setState(() => _isFeatured = v),
              ),
              SwitchListTile(
                title: const Text('Personalizable'),
                subtitle: const Text(
                  'El cliente escribe un texto (p. ej. un nombre)',
                ),
                value: _isCustomizable,
                onChanged: (v) => setState(() => _isCustomizable = v),
              ),
              if (_isCustomizable)
                TextFormField(
                  controller: _customizationLabel,
                  decoration: const InputDecoration(
                    labelText: 'Texto a pedir al cliente',
                    hintText: 'Nombre del bebé',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Opciones a elegir',
            children: [
              const Text(
                'Listas de las que el cliente elige un valor, p. ej. el color '
                'del lazo. No cambian el precio: para eso, usa '
                'variantes.',
              ),
              for (final (index, field) in _choiceFields.indexed)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: field.label,
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                            hintText: 'Color del lazo',
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Ponle un nombre'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: field.options,
                          decoration: const InputDecoration(
                            labelText: 'Valores, separados por comas',
                            hintText: 'Rojo, Azul, Verde',
                          ),
                          validator: (v) =>
                              _ChoiceFieldControllers.split(v ?? '').isEmpty
                              ? 'Añade al menos un valor'
                              : null,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar lista',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(
                          () => _choiceFields.removeAt(index).dispose(),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_choiceFields.length < 10)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir lista'),
                    onPressed: () => setState(
                      () => _choiceFields.add(_ChoiceFieldControllers()),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Variantes',
            children: [
              const Text(
                'Opciones que cambian el precio, p. ej. tamaño y '
                'material. Se crea una variante por cada combinación de '
                'valores; desactiva las que no vendas.',
              ),
              for (final (index, option) in _options.indexed)
                Padding(
                  key: ObjectKey(option),
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: option.name,
                          decoration: const InputDecoration(
                            labelText: 'Opción',
                            hintText: 'Tamaño',
                          ),
                          validator: (v) {
                            final name = (v ?? '').trim().toLowerCase();
                            if (name.isEmpty) return 'Ponle un nombre';
                            final repeated = _options
                                .where(
                                  (o) =>
                                      o.name.text.trim().toLowerCase() == name,
                                )
                                .length;
                            return repeated > 1 ? 'Nombre repetido' : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: option.values,
                          decoration: const InputDecoration(
                            labelText: 'Valores, separados por comas',
                            hintText: '8 cm, 10 cm, 12 cm',
                          ),
                          validator: (v) =>
                              _ChoiceFieldControllers.split(v ?? '').isEmpty
                              ? 'Añade al menos un valor'
                              : null,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar opción',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeOption(index),
                      ),
                    ],
                  ),
                ),
              if (_options.length < maxOptions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir opción'),
                    onPressed: _addOption,
                  ),
                ),
              for (final variant in _variants)
                _VariantEditor(
                  key: ObjectKey(variant),
                  fields: variant,
                  onChanged: () => setState(() {}),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isNew)
            const _Section(
              title: 'Imágenes',
              children: [
                Text('Guarda el producto para poder añadir imágenes.'),
              ],
            )
          else
            _ImagesEditor(
              product: widget.product!,
              onChanged: () => _invalidateCatalog(_p!.id),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isNew ? 'Crear producto' : 'Guardar cambios'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Supplier and box size of the product, from the lists in Ajustes.
class _CostFields extends ConsumerWidget {
  const _CostFields({
    required this.supplierId,
    required this.boxSize,
    required this.onSupplier,
    required this.onBoxSize,
  });

  final String? supplierId;
  final BoxSize? boxSize;
  final ValueChanged<String?> onSupplier;
  final ValueChanged<BoxSize?> onBoxSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider).value;
    final boxes = ref.watch(costSettingsProvider).value;
    // A supplier deleted in the meantime shows as none.
    final known = suppliers?.any((s) => s.id == supplierId) == true
        ? supplierId
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            // Re-created once the list arrives, to show the saved supplier.
            key: ValueKey('supplier-${suppliers != null}'),
            initialValue: known,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Proveedor',
              helperText: 'Se dan de alta en Ajustes',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin proveedor')),
              for (final supplier in suppliers ?? const <Supplier>[])
                DropdownMenuItem(
                  value: supplier.id,
                  child: Text(supplier.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: suppliers == null ? null : onSupplier,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<BoxSize?>(
            initialValue: boxSize,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Caja'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin caja')),
              for (final size in BoxSize.values)
                DropdownMenuItem(
                  value: size,
                  child: Text(
                    boxes == null
                        ? size.apiName
                        : '${size.apiName} · ${formatCents(boxes.priceOf(size))}',
                  ),
                ),
            ],
            onChanged: onBoxSize,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
          ],
        ),
      ),
    );
  }
}

/// Most options a product can combine, and most variants the API accepts.
const maxOptions = 3;
const maxVariants = 100;

/// Text fields of one option: its name and comma-separated values.
class _OptionControllers {
  _OptionControllers(
    VariantOption? option, {
    required void Function(_OptionControllers) onChanged,
  }) : name = TextEditingController(text: option?.name ?? ''),
       values = TextEditingController(text: option?.values.join(', ') ?? ''),
       lastName = option?.name ?? '',
       lastValues = option?.values ?? const [] {
    name.addListener(() => onChanged(this));
    values.addListener(() => onChanged(this));
  }

  final TextEditingController name;
  final TextEditingController values;

  /// Name and values the variants were last arranged with, to spot renames.
  String lastName;
  List<String> lastValues;

  List<String> get currentValues => _ChoiceFieldControllers.split(values.text);

  void dispose() {
    name.dispose();
    values.dispose();
  }
}

/// Text controllers for one variant row; its combination is in
/// `draft.options`.
class _VariantFields {
  _VariantFields(this.draft)
    : sku = TextEditingController(text: draft.sku),
      price = TextEditingController(
        text: draft.priceCents == null ? '' : centsToInput(draft.priceCents!),
      ),
      cost = TextEditingController(
        text: draft.costCents == null ? '' : centsToInput(draft.costCents!),
      );

  final VariantDraft draft;
  final TextEditingController sku;
  final TextEditingController price;
  final TextEditingController cost;

  /// E.g. "10 cm · Cristal"; empty for a product without options.
  String get label => draft.options.values.join(' · ');

  VariantDraft toDraft() => VariantDraft(
    id: draft.id,
    name: label.isEmpty ? 'Default' : label,
    sku: sku.text.trim(),
    options: Map.of(draft.options),
    priceCents: parseCents(price.text),
    // Stock is hidden for now: whatever was stored is kept as is.
    stock: draft.stock,
    isActive: draft.isActive,
    costCents: parseCents(cost.text),
  );

  void dispose() {
    sku.dispose();
    price.dispose();
    cost.dispose();
  }
}

class _VariantEditor extends StatelessWidget {
  const _VariantEditor({
    super.key,
    required this.fields,
    required this.onChanged,
  });

  final _VariantFields fields;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    InputDecoration dense(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      fillColor: AppColors.sageLight,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.sage),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fields.label.isNotEmpty) ...[
              Text(fields.label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    controller: fields.sku,
                    decoration: dense('SKU'),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    controller: fields.price,
                    decoration: dense('Precio (€)', hint: 'Por defecto'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isNotEmpty && parseCents(v!) == null
                        ? 'No válido'
                        : null,
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    controller: fields.cost,
                    decoration: dense('Coste (€)', hint: 'Por defecto'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isNotEmpty && parseCents(v!) == null
                        ? 'No válido'
                        : null,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Switch(
                  value: fields.draft.isActive,
                  onChanged: (v) {
                    fields.draft.isActive = v;
                    onChanged();
                  },
                ),
                const Text('Activa'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagesEditor extends ConsumerStatefulWidget {
  const _ImagesEditor({required this.product, required this.onChanged});

  final Product product;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ImagesEditor> createState() => _ImagesEditorState();
}

class _ImagesEditorState extends ConsumerState<_ImagesEditor> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (files.isEmpty) return;
    await _run(() async {
      final images = ref.read(productImageRepositoryProvider);
      for (final file in files) {
        await images.upload(
          productId: widget.product.id,
          bytes: await file.readAsBytes(),
          fileName: file.name,
        );
      }
    });
  }

  Future<void> _addUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir imagen por URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'https://...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || !url.startsWith('http')) return;
    await _run(
      () => ref
          .read(productImageRepositoryProvider)
          .addUrl(productId: widget.product.id, url: url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product.images;
    return _Section(
      title: 'Imágenes',
      children: [
        if (images.isEmpty)
          const Text('Sin imágenes todavía. La primera será la portada.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final image in images)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox.square(
                      dimension: 110,
                      child: ProductImageView(url: image.url),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton.filledTonal(
                      iconSize: 18,
                      tooltip: 'Eliminar imagen',
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => ref
                                  .read(productImageRepositoryProvider)
                                  .delete(image),
                            ),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _upload,
              icon: const Icon(Icons.upload),
              label: const Text('Subir imágenes'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _addUrl,
              icon: const Icon(Icons.link),
              label: const Text('Añadir por URL'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}

/// Editable choice list: its name and its values as "Rojo, Azul, Verde".
class _ChoiceFieldControllers {
  _ChoiceFieldControllers([ChoiceField? field])
    : label = TextEditingController(text: field?.label ?? ''),
      options = TextEditingController(text: field?.options.join(', ') ?? '');

  final TextEditingController label;
  final TextEditingController options;

  /// Comma-separated values, trimmed, without blanks or repeats.
  static List<String> split(String text) => {
    for (final value in text.split(','))
      if (value.trim().isNotEmpty) value.trim(),
  }.toList();

  ChoiceField toField() =>
      ChoiceField(label: label.text.trim(), options: split(options.text));

  void dispose() {
    label.dispose();
    options.dispose();
  }
}
