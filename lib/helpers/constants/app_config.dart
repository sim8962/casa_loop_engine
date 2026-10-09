/// Configuration injectable à la compilation (`--dart-define`).
abstract final class AppConfig {
  /// Chemin du MBTiles MASTER utilisé comme source d'installation.
  /// Ce fichier est lu seulement : il n'est jamais modifié ni réencodé.
  static const String mbtilesSourcePath = String.fromEnvironment(
    'CASA_LOOP_MBTILES_SOURCE_PATH',
    defaultValue: '/Users/macjam/Desktop/CasaLoopEngine/dev_data/casa_trail_v4_z7_z15.mbtiles',
  );

  /// Nom du fichier d'archive de tuiles Valhalla attendu dans
  /// `<Documents>/routing/` du stockage applicatif.
  static const String routingGraphFileName = 'routing_proof.tar';

  /// Gabarit de configuration Valhalla installé avec l'archive dans le même
  /// dossier ; seuls les chemins y sont réécrits, à la première
  /// configuration du moteur.
  static const String routingConfigTemplateFileName = 'valhalla.template.json';

  /// SHA-256 attendu de l'archive de graphe de preuve, tel que produit sur
  /// le Mac (`tool/routing_proof/graph/routing_proof.tar`). Sert à vérifier
  /// la copie installée sur l'appareil, pas à la modifier.
  static const String routingGraphSha256 = 'c1d68f7bd9b3e34f2949b3dcd46ff70e7926e01af583d159641d7230f1e55039';
}
