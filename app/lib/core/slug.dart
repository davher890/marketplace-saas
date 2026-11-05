/// Turns "Cojín Nube 30x50" into "cojin-nube-30x50".
String slugify(String input) {
  const accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  final lower = input
      .toLowerCase()
      .split('')
      .map((c) => accents[c] ?? c)
      .join();
  return lower
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
