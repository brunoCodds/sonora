enum SortField {
  title('Título'),
  artist('Artista'),
  album('Álbum'),
  year('Ano'),
  dateAdded('Adicionado recentemente'),
  duration('Duração');

  final String label;
  const SortField(this.label);

  static SortField fromName(String? name) {
    return SortField.values.firstWhere(
      (f) => f.name == name,
      orElse: () => SortField.title,
    );
  }
}
