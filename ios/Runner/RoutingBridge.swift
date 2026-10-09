import Flutter
import Valhalla

/// Pont natif du canal `casa/routing` vers le moteur Valhalla embarqué.
///
/// `configure` et `route` sont exécutés sur une file série dédiée, hors
/// thread principal : la construction du moteur (mmap du graphe) est aussi
/// coûteuse qu'une requête, et une seule instance est réutilisée pour toute
/// la durée de vie de l'application. Toute exception native est convertie en
/// `FlutterError`, jamais propagée au thread appelant.
final class RoutingBridge {

    static let channelName = "casa/routing"

    private let queue = DispatchQueue(label: "casa.routing", qos: .userInitiated)
    private var engine: Valhalla?

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configure":
            guard let args = call.arguments as? [String: Any],
                  let configPath = args["configPath"] as? String else {
                result(FlutterError(code: "bad_args", message: "configPath manquant", details: nil))
                return
            }
            queue.async { [weak self] in
                guard let self else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "released", message: "RoutingBridge libéré", details: nil))
                    }
                    return
                }
                do {
                    let newEngine = try Valhalla(configPath: configPath)
                    self.engine?.close()
                    self.engine = newEngine
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "configure_failed",
                            message: "Valhalla init impossible : \(error)",
                            details: nil,
                        ))
                    }
                }
            }
        case "route":
            guard let args = call.arguments as? [String: Any],
                  let request = args["request"] as? String else {
                result(FlutterError(code: "bad_args", message: "request manquant", details: nil))
                return
            }
            queue.async { [weak self] in
                guard let self else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "released", message: "RoutingBridge libéré", details: nil))
                    }
                    return
                }
                do {
                    guard let engine = self.engine else {
                        throw NSError(
                            domain: "casa.routing",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Moteur non configuré"],
                        )
                    }
                    let response = try engine.route(rawRequest: request)
                    DispatchQueue.main.async { result(response) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "route_failed",
                            message: "Calcul Valhalla impossible : \(error)",
                            details: nil,
                        ))
                    }
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
