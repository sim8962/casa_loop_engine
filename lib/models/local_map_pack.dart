/// Pack cartographique offline installé localement : le MBTiles copié et le
/// style MapLibre qui le référence.
class LocalMapPack {
  const LocalMapPack({required this.mbtilesPath, required this.stylePath});

  final String mbtilesPath;
  final String stylePath;
}
