class Playlist {
  final int id;
  final String name;
  final DateTime createdAt;

  /// IDs das músicas, na ordem em que aparecem na playlist.
  final List<int> songIds;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.songIds,
  });

  Playlist copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    List<int>? songIds,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      songIds: songIds ?? this.songIds,
    );
  }

  @override
  bool operator ==(Object other) => other is Playlist && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
