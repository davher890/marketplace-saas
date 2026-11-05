class Category {
  const Category({
    required this.id,
    required this.name,
    required this.slug,
    this.parentId,
    this.description,
    this.imageUrl,
    this.position = 0,
    this.isActive = true,
    this.productCount = 0,
  });

  final String id;
  final String? parentId;
  final String name;
  final String slug;
  final String? description;
  final String? imageUrl;
  final int position;
  final bool isActive;

  /// Products directly in this category (only filled by the admin API).
  final int productCount;

  bool get isRoot => parentId == null;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    parentId: json['parent_id'] as String?,
    name: json['name'] as String,
    slug: json['slug'] as String,
    description: json['description'] as String?,
    imageUrl: json['image_url'] as String?,
    position: json['position'] as int? ?? 0,
    isActive: json['is_active'] as bool? ?? true,
    productCount: json['product_count'] as int? ?? 0,
  );
}

/// Category with its direct children, used to build the navigation menu.
class CategoryNode {
  const CategoryNode(this.category, this.children);

  final Category category;
  final List<Category> children;

  /// Builds a two-level tree from a flat, position-ordered list.
  static List<CategoryNode> buildTree(List<Category> categories) {
    final roots = categories.where((c) => c.isRoot).toList();
    return [
      for (final root in roots)
        CategoryNode(
          root,
          categories.where((c) => c.parentId == root.id).toList(),
        ),
    ];
  }
}
