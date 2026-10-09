import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/services/objectbox/objectbox_store.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Surveille le cycle de vie de l'application pour fermer proprement le store
/// ObjectBox quand l'application passe en arrière-plan, réduisant le risque de
/// base non propre en cas de kill par le système.
class ObjectBoxLifecycle extends GetxService with WidgetsBindingObserver {
  ObjectBoxLifecycle(this._store);

  final ObjectBoxStore _store;

  void listen() {
    Diag.event('ObjectBoxLifecycle.listen');
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Diag.event('ObjectBoxLifecycle.didChangeAppLifecycleState', 'state=$state');
    if (state == AppLifecycleState.detached) {
      _store.close();
    }
  }

  @override
  void onClose() {
    Diag.event('ObjectBoxLifecycle.onClose');
    WidgetsBinding.instance.removeObserver(this);
    _store.close();
    super.onClose();
  }
}
