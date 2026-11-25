/// One column the monthly orders file (Excel) can have.
class ExportColumn {
  const ExportColumn({required this.key, required this.label});

  final String key;
  final String label;

  factory ExportColumn.fromJson(Map<String, dynamic> json) =>
      ExportColumn(key: json['key'] as String, label: json['label'] as String);
}

/// Every column the file can have (in the default order) and the ones the
/// admin chose, in their order.
class ExportColumns {
  const ExportColumns({required this.available, required this.selected});

  final List<ExportColumn> available;
  final List<String> selected;

  factory ExportColumns.fromJson(Map<String, dynamic> json) => ExportColumns(
    available: [
      for (final column in json['available'] as List)
        ExportColumn.fromJson(column as Map<String, dynamic>),
    ],
    selected: [for (final key in json['selected'] as List) key as String],
  );
}
