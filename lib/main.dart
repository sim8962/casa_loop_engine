import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import 'package:casa_loop_engine/app.dart';
import 'package:casa_loop_engine/bindings/app_binding.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

// Commandes utiles :
// flutter build apk --profile
// cd ios && flutter pub get && pod install --repo-update
// dart run build_runner build --delete-conflicting-outputs
Future<void> main() async {
  final boot = Diag.start('main');
  Diag.sync('main.ensureInitialized', WidgetsFlutterBinding.ensureInitialized);
  try {
    await Diag.future('main.GetStorage.init', GetStorage.init);
    await AppBinding.initializeGlobalServices();
  } catch (exception, stack) {
    Diag.error('main.storageInitialization', exception, stack);
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Stockage local indisponible\n$exception'),
              ),
            ),
          ),
        ),
      ),
    );
    boot.fail(exception, stack);
    return;
  }
  runApp(const CasaLoopApp());
  boot.end('appStarted');
  // Délai entre la fin de l'initialisation et la première frame rendue ;
  // distinct de la durée de construction des widgets.
  Diag.untilFirstFrame('main.firstFrame');
}
