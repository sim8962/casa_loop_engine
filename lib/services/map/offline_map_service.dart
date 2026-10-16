import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'package:casa_loop_engine/helpers/constants/app_config.dart';
import 'package:casa_loop_engine/helpers/constants/color_hex.dart';
import 'package:casa_loop_engine/models/local_map_pack.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Installe et expose le pack cartographique offline.
///
/// Le MBTiles source (MASTER) est uniquement lu : il n'est jamais modifié.
/// La copie est atomique (fichier `.partial` renommé une fois complet et
/// vérifié) afin qu'une interruption ne laisse pas de MBTiles tronqué
/// exploitable. Une copie déjà installée n'est jamais remplacée tant
/// qu'elle satisfait le contrôle d'identité rapide (taille exacte et
/// en-tête SQLite) ; une copie invalide n'est réparée que depuis une
/// source dont l'empreinte SHA-256 correspond au pack de référence.
class OfflineMapService {
  OfflineMapService({required this.sourcePath});

  static const fileName = 'casa_trail_v4_z7_z15.mbtiles';
  static const styleFileName = 'casa_trail_style.json';

  /// Signature des 16 premiers octets de tout fichier SQLite/MBTiles :
  /// `SQLite format 3\0`. Contrôle rapide de la copie installée à chaque
  /// lancement — le hachage complet n'a lieu qu'à l'installation.
  static const _sqliteMagic = <int>[
    0x53,
    0x51,
    0x4c,
    0x69,
    0x74,
    0x65,
    0x20,
    0x66,
    0x6f,
    0x72,
    0x6d,
    0x61,
    0x74,
    0x20,
    0x33,
    0x00,
  ];

  final String sourcePath;

  Future<LocalMapPack> ensureInstalled() => Diag.future(
    'OfflineMapService.ensureInstalled',
    () async {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final mapPackDirectory = Directory('${documentsDirectory.path}/map_packs');
      final destination = File('${mapPackDirectory.path}/$fileName');

      if (await _isUsableInstall(destination)) {
        Diag.event(
          'OfflineMapService.ensureInstalled.alreadyInstalled',
          'bytes=${await destination.length()}',
        );
      } else {
        await _copyTo(destination, mapPackDirectory, documentsDirectory);
      }

      final styleFile = File('${mapPackDirectory.path}/$styleFileName');
      await styleFile.writeAsString(jsonEncode(_styleFor(destination.path)), flush: true);

      return LocalMapPack(mbtilesPath: destination.path, stylePath: styleFile.path);
    },
    params: 'source=$sourcePath',
    result: (pack) => 'mbtiles=${pack.mbtilesPath}',
  );

  /// La copie installée est réutilisable si elle a exactement la taille du
  /// pack de référence et l'en-tête SQLite — contrôle en lecture bornée,
  /// sans hachage des ~450 Mo à chaque lancement.
  Future<bool> _isUsableInstall(File destination) async {
    if (!await destination.exists()) return false;
    if (await destination.length() != AppConfig.mbtilesSizeBytes) {
      Diag.event('OfflineMapService._isUsableInstall.badSize', 'path=${destination.path}');
      return false;
    }
    final header = BytesBuilder();
    await for (final chunk in destination.openRead(0, _sqliteMagic.length)) {
      header.add(chunk);
    }
    final bytes = header.takeBytes();
    for (var i = 0; i < _sqliteMagic.length; i++) {
      if (i >= bytes.length || bytes[i] != _sqliteMagic[i]) {
        Diag.event('OfflineMapService._isUsableInstall.badHeader', 'path=${destination.path}');
        return false;
      }
    }
    return true;
  }

  Future<void> _copyTo(File destination, Directory directory, Directory documentsDirectory) async {
    final op = Diag.start('OfflineMapService._copyTo', 'src=$sourcePath');
    try {
      final source = File(sourcePath.startsWith('/') ? sourcePath : '${documentsDirectory.path}/$sourcePath');
      if (!await source.exists()) {
        throw FileSystemException(
          await destination.exists()
              ? 'Carte installée invalide ou incomplète et MASTER MBTiles '
                    'source introuvable : déposez $fileName dans Documents'
              : 'MASTER MBTiles source introuvable : déposez $fileName '
                    'dans Documents',
          source.path,
        );
      }

      final sourceLength = await source.length();
      if (sourceLength == 0) {
        throw FileSystemException('MASTER MBTiles source vide', source.path);
      }
      if (sourceLength != AppConfig.mbtilesSizeBytes) {
        throw FileSystemException(
          'Source MBTiles incompatible : taille $sourceLength o, '
          'attendue ${AppConfig.mbtilesSizeBytes} o pour $fileName',
          source.path,
        );
      }

      await directory.create(recursive: true);
      final partial = File('${destination.path}.partial');

      try {
        if (await partial.exists()) {
          await partial.delete();
        }
        await source.openRead().pipe(partial.openWrite());
        final copiedLength = await partial.length();
        if (copiedLength != sourceLength) {
          throw FileSystemException(
            'Copie MBTiles incomplète ($copiedLength/$sourceLength octets)',
            partial.path,
          );
        }
        await _verifyPartialSha256(partial);
        await partial.rename(destination.path);
        op.end('bytes=$copiedLength');
      } catch (_) {
        if (await partial.exists()) {
          await partial.delete();
        }
        rethrow;
      }
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    }
  }

  /// Empreinte SHA-256 de la copie, lue en flux — jamais chargée en entier
  /// en mémoire — avant que le fichier `.partial` ne prenne la place de la
  /// destination. Refuse l'installation si le contenu copié n'est pas le
  /// pack de référence.
  Future<void> _verifyPartialSha256(File partial) async {
    final String actual;
    try {
      actual = (await sha256.bind(partial.openRead()).first).toString();
    } catch (error) {
      throw FileSystemException('Empreinte de la copie MBTiles illisible — $error', partial.path);
    }
    if (actual != AppConfig.mbtilesSha256) {
      throw FileSystemException(
        'La source MBTiles ne correspond pas au pack attendu '
        '(SHA-256 attendu ${AppConfig.mbtilesSha256}, lu $actual)',
        partial.path,
      );
    }
  }

  Map<String, Object> _styleFor(String mbtilesPath) => Diag.sync(
    'OfflineMapService._styleFor',
    () => {
      'version': 8,
      'name': 'Casa Loop Offline Raster',
      'sources': {
        'casa-raster': {
          'type': 'raster',
          'url': 'mbtiles://$mbtilesPath',
          'tileSize': 256,
          'minzoom': 7,
          'maxzoom': 15,
        },
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': ColorHex.canvas},
        },
        {'id': 'casa-raster-layer', 'type': 'raster', 'source': 'casa-raster', 'minzoom': 7, 'maxzoom': 15},
      ],
    },
  );
}
