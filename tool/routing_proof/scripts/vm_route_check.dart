// Controle technique : appelle OfflineRoutingService.computeFirstSegment
// dans le simulateur iOS en cours d'execution, via le service VM Dart.
// evaluate() retourne la Future sans l'attendre : le resultat est depose
// dans une String enregistree via Get.put, relue par sondage.
// Usage : dart tool/routing_proof/scripts/vm_route_check.dart <wsUri>
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final ws = await WebSocket.connect(args[0]);
  var idSeq = 0;
  final pending = <int, Completer<Map<String, dynamic>>>{};
  ws.listen((data) {
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    final id = msg['id'];
    if (id is int && pending.containsKey(id)) {
      pending.remove(id)!.complete(msg);
    }
  });
  Future<Map<String, dynamic>> rpc(String method, Map<String, dynamic> params) {
    final id = ++idSeq;
    final completer = Completer<Map<String, dynamic>>();
    pending[id] = completer;
    ws.add(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
    return completer.future;
  }

  final vm = await rpc('getVM', {});
  final isolates = (vm['result']['isolates'] as List).cast<Map<String, dynamic>>();
  final isolateId = isolates.firstWhere((i) => i['name'] == 'main')['id'] as String;

  final iso = await rpc('getIsolate', {'isolateId': isolateId});
  final libraries = (iso['result']['libraries'] as List).cast<Map<String, dynamic>>();
  final libId =
      libraries.firstWhere((l) => (l['uri'] as String).endsWith('offline_routing_service.dart'))['id']
          as String;

  Future<String?> eval(String expression) async {
    final res = await rpc('evaluate', {'isolateId': isolateId, 'targetId': libId, 'expression': expression});
    final result = res['result'] as Map<String, dynamic>?;
    final error = res['error'];
    if (error != null) return 'RPC_ERR $error';
    if (result == null) return 'NO_RESULT ${jsonEncode(res)}';
    if (result['type'] == 'ErrorRef') return 'EVAL_ERR ${result['message']}';
    return (result['valueAsString'] as String?) ?? result['kind'] as String?;
  }

  // Lance le calcul ; la completion affiche son verdict via print(),
  // visible dans le flux `flutter run` (prefixe VMROUTE).
  const launch =
      "OfflineRoutingService().computeFirstSegment(startLat:33.5898,startLon:-7.5902,endLat:33.6084,endLon:-7.6326)"
      ".then((r)=>print('VMROUTE OK dist='+r.distanceKm.toStringAsFixed(3)+'km dur='+r.durationSeconds.toStringAsFixed(1)+'s'"
      "+' pts='+r.geometry.length.toString()+' snap='+r.startSnapDistanceMeters.toStringAsFixed(1)+'/'+r.endSnapDistanceMeters.toStringAsFixed(1)+'m'))"
      ".catchError((e)=>print('VMROUTE ERR '+e.toString()))";
  stdout.writeln('launch: ${await eval(launch)}');
  await ws.close();
  exit(0);
}
