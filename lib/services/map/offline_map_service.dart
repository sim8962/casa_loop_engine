import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:casa_loop_engine/helpers/constants/color_hex.dart';
import 'package:casa_loop_engine/models/local_map_pack.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Installe et expose le pack cartographique offline.
///
/// Le MBTiles source (MASTER) est uniquement lu : il n'est jamais modifié.
/// La copie est atomique (fichier `.partial` renommé une fois complet) afin
/// qu'une interruption ne laisse pas de MBTiles tronqué exploitable.
class OfflineMapService {
  OfflineMapService({required this.sourcePath});

  static const fileName = 'casa_trail_v4_z7_z15.mbtiles';
  static const styleFileName = 'casa_trail_style.json';

  final String sourcePath;

  Future<LocalMapPack> ensureInstalled() => Diag.future(
    'OfflineMapService.ensureInstalled',
    () async {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final mapPackDirectory = Directory('${documentsDirectory.path}/map_packs');
      final destination = File('${mapPackDirectory.path}/$fileName');

      if (!await destination.exists() || await destination.length() == 0) {
        await _copyTo(destination, mapPackDirectory, documentsDirectory);
      } else {
        Diag.event(
          'OfflineMapService.ensureInstalled.alreadyInstalled',
          'bytes=${await destination.length()}',
        );
      }

      final styleFile = File('${mapPackDirectory.path}/$styleFileName');
      await styleFile.writeAsString(jsonEncode(_styleFor(destination.path)), flush: true);

      return LocalMapPack(mbtilesPath: destination.path, stylePath: styleFile.path);
    },
    params: 'source=$sourcePath',
    result: (pack) => 'mbtiles=${pack.mbtilesPath}',
  );

  Future<void> _copyTo(File destination, Directory directory, Directory documentsDirectory) async {
    final op = Diag.start('OfflineMapService._copyTo', 'src=$sourcePath');
    try {
      final source = File(sourcePath.startsWith('/') ? sourcePath : '${documentsDirectory.path}/$sourcePath');
      if (!await source.exists()) {
        throw FileSystemException('MASTER MBTiles source introuvable', source.path);
      }

      final sourceLength = await source.length();
      if (sourceLength == 0) {
        throw FileSystemException('MASTER MBTiles source vide', source.path);
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
