import ExpoModulesCore
import UIKit

/**
 * Hosts one Elpian session with the Swift core rendering to UIKit. `kind` and
 * `optionsJson` are applied together after a props batch, so changing both
 * re-opens the session once.
 */
final class ElpianExpoView: ExpoView {
  let onElpianEvent = EventDispatcher()
  let host: ElpianHostView

  var kind = "json"
  var optionsJson = "{}"
  private var openedKind: String?
  private var openedOptions: String?
  private var removeListener: (() -> Void)?

  required init(appContext: AppContext? = nil) {
    host = ElpianHostView(frame: .zero)
    super.init(appContext: appContext)
    // React may remove and re-add native views; the session lives until React drops the view.
    host.closeOnDetach = false
    host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.frame = bounds
    addSubview(host)
    removeListener = host.onAnyEventJson { [weak self] event, payloadJson in
      self?.onElpianEvent(["event": event, "payloadJson": payloadJson])
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    host.frame = bounds
  }

  func applyProps() {
    if kind == openedKind && optionsJson == openedOptions { return }
    openedKind = kind
    openedOptions = optionsJson
    host.openJson(kind: kind, optionsJson: optionsJson, done: nil)
  }

  func dispose() {
    removeListener?()
    removeListener = nil
    host.close(done: nil)
  }
}
