package dev.elpian.expo

import dev.elpian.android.Elpian
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.functions.Queues
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

/** `requireNativeView('Elpian')` — see src/ElpianView.tsx. */
class ElpianExpoModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("Elpian")

    OnCreate {
      appContext.reactContext?.let { Elpian.install(it.applicationContext) }
    }

    Constant("coreVersion") { Elpian.coreVersion }

    View(ElpianExpoView::class) {
      Events("onElpianEvent")

      Prop("kind") { view: ElpianExpoView, kind: String ->
        view.kind = kind
      }

      Prop("optionsJson") { view: ElpianExpoView, json: String ->
        view.optionsJson = json
      }

      OnViewDidUpdateProps { view: ElpianExpoView ->
        view.applyProps()
      }

      OnViewDestroys { view: ElpianExpoView ->
        view.dispose()
      }

      AsyncFunction("call") { view: ElpianExpoView, method: String, argsJson: String, promise: Promise ->
        view.host.callJson(method, argsJson) { ok, valueJson ->
          if (ok) promise.resolve(valueJson)
          else promise.reject(CodedException("ERR_ELPIAN_CALL", valueJson, null))
        }
      }.runOnQueue(Queues.MAIN)

      AsyncFunction("close") { view: ElpianExpoView, promise: Promise ->
        view.host.close { promise.resolve(null) }
      }.runOnQueue(Queues.MAIN)
    }
  }
}
