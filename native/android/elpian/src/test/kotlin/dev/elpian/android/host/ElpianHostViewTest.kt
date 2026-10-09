package dev.elpian.android.host

import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import dev.elpian.android.Elpian
import dev.elpian.android.ElpianHostView
import dev.elpian.android.ElpianOptions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import android.os.Looper

/**
 * End to end on the Android framework (Robolectric): a session opened on an
 * [ElpianHostView] is lowered, laid out and rendered by the Kotlin core into
 * real Views, and view events flow back into the session.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ElpianHostViewTest {
    private val context = ApplicationProvider.getApplicationContext<android.app.Application>()

    private fun idle() {
        repeat(5) { shadowOf(Looper.getMainLooper()).idle() }
    }

    private fun host(): ElpianHostView {
        Elpian.install(context, ElpianOptions(elpianVm = false, quickJs = false, wasm = false, godot = false))
        val view = ElpianHostView(context)
        val parent = FrameLayout(context)
        parent.addView(view, ViewGroup.LayoutParams(400, 600))
        parent.measure(View.MeasureSpec.makeMeasureSpec(400, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(600, View.MeasureSpec.EXACTLY))
        parent.layout(0, 0, 400, 600)
        return view
    }

    private fun count(v: View): Int = 1 + if (v is ViewGroup) (0 until v.childCount).sumOf { count(v.getChildAt(it)) } else 0

    @Test
    fun jsonSessionRendersNativeViews() {
        val view = host()
        var failure: Throwable? = Throwable("not opened")
        val tree = mapOf(
            "type" to "div",
            "style" to mapOf("padding" to "16px", "backgroundColor" to "#eeeeee"),
            "children" to listOf(
                mapOf("type" to "h1", "props" to mapOf("text" to "Hello")),
                mapOf("type" to "p", "props" to mapOf("text" to "Rendered by the Kotlin core")),
                mapOf("type" to "Container", "props" to mapOf("style" to mapOf("width" to 50, "height" to 50, "backgroundColor" to "red"))),
            ),
        )
        view.open("json", mapOf("view" to tree)) { failure = it }
        idle()
        assertNull(failure)
        assertTrue("expected rendered views, got ${count(view.surface)}", count(view.surface) > 4)
        view.close()
        idle()
    }

    @Test
    fun eventsReachListenersAndErrorsAreReported() {
        val view = host()
        val events = ArrayList<String>()
        view.onAnyEvent { e, _ -> events += e }
        var failure: Throwable? = null
        view.open("no-such-kind", emptyMap()) { failure = it }
        idle()
        assertTrue(failure != null)
        assertTrue(events.contains("error"))
    }

    @Test
    fun callJsonRoundTrips() {
        val view = host()
        view.open("json", mapOf("view" to mapOf("type" to "Text", "props" to mapOf("text" to "x"))))
        idle()
        var reply: Pair<Boolean, String>? = null
        view.callJson("no_such_method", "[]") { ok, value -> reply = ok to value }
        idle()
        assertEquals(false, reply?.first)
    }
}
