import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/money.dart';
import '../../core/slug.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../repositories/admin_repository.dart';
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

  /// Name of the single option dimension (e.g. "Talla"), empty if none.
  late final _optionName = TextEditingController(
    text: _p?.variants.expand((v) => v.options.keys).firstOrNull ?? '',
  );

  /// Categories the product is listed in; the first one is its main one.
  late final List<String> _categoryIds = [...?_p?.categoryIds];
  late bool _isActive = _p?.isActive ?? true;
  late bool _isFeatured = _p?.isFeatured ?? false;
  late bool _isCustomizable = _p?.isCustomizable ?? false;
  late final List<_VariantFields> _variants = (_p?.variants.isNotEmpty ?? false)
      ? _p!.variants
            .map((v) => _VariantFields(VariantDraft.fromVariant(v)))
            .toList()
      : [_VariantFields(VariantDraft())];
  bool _slugEdited = false;
  bool _saving = false;

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
      _customizationLabel,
      _optionName,
    ]) {
      c.dispose();
    }
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final optionName = _optionName.text.trim();
    final drafts = [
      for (final v in _variants) v.toDraft(optionName: optionName),
    ];
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
      isActive: _isActive,
      isFeatured: _isFeatured,
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
                  onPressed: () => context.go('/product/${_p!.slug}'),
                  icon: const Icon(Icons.open_in_new),
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
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Precio (€) *'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) =>
                    parseCents(v ?? '') == null ? 'Importe no válido' : null,
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
            title: 'Variantes',
            children: [
              TextFormField(
                controller: _optionName,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la opción',
                  hintText: 'Talla, Color...',
                  helperText: 'Déjalo vacío si el producto no tiene opciones',
                ),
              ),
              for (final (index, variant) in _variants.indexed)
                _VariantEditor(
                  key: ObjectKey(variant),
                  fields: variant,
                  canRemove: _variants.length > 1,
                  onRemove: () =>
                      setState(() => _variants.removeAt(index).dispose()),
                  onChanged: () => setState(() {}),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _variants.add(_VariantFields(VariantDraft(name: ''))),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir variante'),
                ),
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

/// Text controllers for one variant row.
class _VariantFields {
  _VariantFields(this.draft)
    : name = TextEditingController(
        text: draft.name == 'Default' ? '' : draft.name,
      ),
      sku = TextEditingController(text: draft.sku),
      price = TextEditingController(
        text: draft.priceCents == null ? '' : centsToInput(draft.priceCents!),
      ),
      stock = TextEditingController(text: draft.stock?.toString() ?? '');

  final VariantDraft draft;
  final TextEditingController name;
  final TextEditingController sku;
  final TextEditingController price;
  final TextEditingController stock;

  VariantDraft toDraft({required String optionName}) {
    final value = name.text.trim();
    return VariantDraft(
      id: draft.id,
      name: value.isEmpty ? 'Default' : value,
      sku: sku.text.trim(),
      options: optionName.isNotEmpty && value.isNotEmpty
          ? {optionName: value}
          : {},
      priceCents: parseCents(price.text),
      stock: int.tryParse(stock.text.trim()),
      isActive: draft.isActive,
    );
  }

  void dispose() {
    name.dispose();
    sku.dispose();
    price.dispose();
    stock.dispose();
  }
}

class _VariantEditor extends StatelessWidget {
  const _VariantEditor({
    super.key,
    required this.fields,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final _VariantFields fields;
  final bool canRemove;
  final VoidCallback onRemove;
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
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: fields.name,
                    decoration: dense('Valor', hint: '2 años'),
                  ),
                ),
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
                    controller: fields.stock,
                    decoration: dense('Stock', hint: 'Por encargo'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final text = (v ?? '').trim();
                      if (text.isEmpty) return null;
                      final n = int.tryParse(text);
                      return n == null || n < 0 ? 'No válido' : null;
                    },
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
                const Spacer(),
                if (canRemove)
                  TextButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Quitar'),
                  ),
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
      final repo = ref.read(adminRepositoryProvider);
      for (final file in files) {
        await repo.uploadProductImage(
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
          .read(adminRepositoryProvider)
          .addProductImageUrl(productId: widget.product.id, url: url),
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
                                  .read(adminRepositoryProvider)
                                  .deleteProductImage(image),
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
