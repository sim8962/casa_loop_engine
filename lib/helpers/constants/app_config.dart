/// Configuration injectable à la compilation (`--dart-define`).
abstract final class AppConfig {
  /// Chemin du MBTiles MASTER utilisé comme source d'installation.
  /// Ce fichier est lu seulement : il n'est jamais modifié ni réencodé.
  /// Par défaut, source relative au dossier Documents de l’application.
  /// Un chemin de développement reste injectable explicitement.
  static const String mbtilesSourcePath = String.fromEnvironment(
    'CASA_LOOP_MBTILES_SOURCE_PATH',
    defaultValue: 'casa_trail_v4_z7_z15.mbtiles',
  );

  /// Identité du pack carte attendu : taille en octets et empreinte
  /// SHA-256 du MBTiles `casa_trail_v4_z7_z15.mbtiles`, mesurées sur le
  /// fichier de référence (`dev_data/`, hors Git). Elles servent à
  /// valider la source déposée et la copie installée — jamais à la
  /// modifier. La taille permet un contrôle rapide à chaque lancement ;
  /// l'empreinte n'est calculée qu'à l'installation (lecture en flux).
  static const int mbtilesSizeBytes = 471752704;
  static const String mbtilesSha256 = '1695a6a411b96ec95bb2fcdb4c323ca8c6733f3bf6bdceff38d8f2010a50d321';

  /// Nom du fichier d'archive de tuiles Valhalla attendu dans
  /// `<Documents>/routing/` du stockage applicatif. Le nom change avec le
  /// graphe : un pack régional remplace le pack de preuve, sans réutiliser
  /// silencieusement l'ancien fichier installé sous l'ancien nom.
  static const String routingGraphFileName = 'routing_regional.tar';

  /// Gabarit de configuration Valhalla installé avec l'archive dans le même
  /// dossier ; seuls les chemins y sont réécrits, à la première
  /// configuration du moteur.
  static const String routingConfigTemplateFileName = 'valhalla.template.json';

  /// SHA-256 attendu de l'archive de graphe régional, telle que produite
  /// sur le Mac (`tool/routing_regional/graph/routing_regional.tar`). Sert
  /// à vérifier la copie installée sur l'appareil, pas à la modifier.
  static const String routingGraphSha256 = '090c7a4f07ff90a3ac2845f378d712599e4ebd428432e660030831dc55c4456a';
}
