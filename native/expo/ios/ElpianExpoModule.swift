import ExpoModulesCore

/// `requireNativeView('Elpian')` — see src/ElpianView.tsx.
public final class ElpianExpoModule: Module {
  public func definition() -> ModuleDefinition {
    Name("Elpian")

    OnCreate {
      DispatchQueue.main.async { _ = Elpian.install() }
    }

    Constant("coreVersion") { Elpian.coreVersion }

    View(ElpianExpoView.self) {
      Events("onElpianEvent")

      Prop("kind") { (view: ElpianExpoView, kind: String) in
        view.kind = kind
      }

      Prop("optionsJson") { (view: ElpianExpoView, json: String) in
        view.optionsJson = json
      }

      OnViewDidUpdateProps { (view: ElpianExpoView) in
        view.applyProps()
      }

      AsyncFunction("call") { (view: ElpianExpoView, method: String, argsJson: String, promise: Promise) in
        view.host.callJson(method: method, argsJson: argsJson) { ok, valueJson in
          if ok {
            promise.resolve(valueJson)
          } else {
            promise.reject("ERR_ELPIAN_CALL", valueJson)
          }
        }
      }.runOnQueue(.main)

      AsyncFunction("close") { (view: ElpianExpoView, promise: Promise) in
        view.host.close { promise.resolve(nil) }
      }.runOnQueue(.main)
    }
  }
}
