package dev.elpian.expo

import android.content.Context
import android.view.ViewGroup
import dev.elpian.android.ElpianHostView
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.viewevent.EventDispatcher
import expo.modules.kotlin.views.ExpoView

/**
 * Hosts one Elpian session. `kind` and `optionsJson` are applied together
 * after a props batch (see [ElpianExpoModule]'s OnViewDidUpdateProps), so a
 * change to both re-opens the session once.
 */
class ElpianExpoView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
  private val onElpianEvent by EventDispatcher()

  val host = ElpianHostView(context).also {
    // React Native may detach and re-attach views (e.g. in lists); the session
    // lives until the view is dropped by React.
    it.closeOnDetach = false
    addView(it, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
  }

  var kind: String = "json"
  var optionsJson: String = "{}"
  private var openedKind: String? = null
  private var openedOptions: String? = null

  init {
    host.onAnyEventJson { event, payloadJson ->
      onElpianEvent(mapOf("event" to event, "payloadJson" to payloadJson))
    }
  }

  /** Re-open when the session-defining props changed. */
  fun applyProps() {
    if (kind == openedKind && optionsJson == openedOptions) return
    openedKind = kind
    openedOptions = optionsJson
    host.openJson(kind, optionsJson)
  }

  // ExpoView lays children out with React's frames; keep the host filling us.
  override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
    host.layout(0, 0, r - l, b - t)
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    host.measure(
      MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.EXACTLY),
    )
  }

  fun dispose() {
    host.dispose()
  }
}
