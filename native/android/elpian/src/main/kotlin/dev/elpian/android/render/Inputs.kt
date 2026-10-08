package dev.elpian.android.render

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.SpannableString
import android.text.Spanned
import android.text.TextWatcher
import android.text.style.AbsoluteSizeSpan
import android.text.style.MetricAffectingSpan
import android.text.TextPaint
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.AutoCompleteTextView
import android.widget.BaseAdapter
import android.widget.FrameLayout
import android.widget.Spinner
import android.widget.TextView
import dev.elpian.core.css.M3
import dev.elpian.core.render.TextStyleSpec
import dev.elpian.core.render.ViewEvent
import kotlin.math.max
import kotlin.math.roundToInt

/** Apply a [TextStyleSpec] to a native TextView (controls). */
internal fun applyTextStyle(tv: TextView, s: TextStyleSpec, density: Float) {
    tv.setTextSize(TypedValue.COMPLEX_UNIT_PX, (s.fontSize * density).toFloat())
    tv.setTextColor(s.color)
    tv.typeface = ElpianFonts.typeface(s.fontFamily, s.fontWeight, s.italic)
    tv.letterSpacing = if (s.fontSize > 0) (s.letterSpacing / s.fontSize).toFloat() else 0f
    val h = s.height
    if (h != null && h > 0 && Build.VERSION.SDK_INT >= 28) tv.setLineHeight(max(1, (h * s.fontSize * density).roundToInt()))
    var flags = tv.paintFlags and (Paint.UNDERLINE_TEXT_FLAG or Paint.STRIKE_THRU_TEXT_FLAG).inv()
    if (s.decoration and 1 != 0) flags = flags or Paint.UNDERLINE_TEXT_FLAG
    if (s.decoration and 4 != 0) flags = flags or Paint.STRIKE_THRU_TEXT_FLAG
    tv.paintFlags = flags
}

/** A span sizing / styling the hint like `::placeholder`. */
private class HintSpan(val s: TextStyleSpec, val density: Float) : MetricAffectingSpan() {
    override fun updateMeasureState(tp: TextPaint) {
        tp.textSize = (s.fontSize * density).toFloat()
        tp.typeface = ElpianFonts.typeface(s.fontFamily, s.fontWeight, s.italic)
    }

    override fun updateDrawState(tp: TextPaint) {
        updateMeasureState(tp)
    }
}

/**
 * The `textInput` view kind: an EditText (with an autocomplete list for
 * `suggestions`) inside Material chrome — outline / underline / none, fill,
 * radius, a border that thickens on focus without shifting the text.
 */
@SuppressLint("ViewConstructor")
class TextInputLeaf(context: Context, private val owner: ElpianView) : FrameLayout(context) {
    val input = AutoCompleteTextView(context)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var props: Map<String, Any?> = emptyMap()
    private var suppress = false
    private var focused = false
    private var valueAtFocus: String? = null
    private var multiline = false
    private var inputTypeName = "text"
    private var readOnly = false

    init {
        setWillNotDraw(false)
        clipChildren = true
        input.background = null
        input.setPadding(0, 0, 0, 0)
        input.includeFontPadding = false
        input.threshold = 1
        input.setTextColor(M3.onSurface)
        addView(input, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        input.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (!suppress) emit("input", s?.toString() ?: "")
            }
        })
        input.setOnFocusChangeListener { _, has ->
            focused = has
            applyChrome()
            if (has) {
                valueAtFocus = input.text.toString()
                emit("focus", null)
            } else {
                val v = input.text.toString()
                if (valueAtFocus != null && valueAtFocus != v) emit("change", v)
                valueAtFocus = null
                emit("blur", null)
            }
        }
        input.setOnKeyListener { _, keyCode, event ->
            val type = if (event.action == KeyEvent.ACTION_DOWN) "keydown" else if (event.action == KeyEvent.ACTION_UP) "keyup" else null
            if (type != null && type == "keydown") {
                owner.host.emit(ViewEvent(id = owner.viewId, type = "keydown", key = Keys.name(event), keyCode = Keys.domKeyCode(event), altKey = event.isAltPressed, ctrlKey = event.isCtrlPressed, shiftKey = event.isShiftPressed, metaKey = event.isMetaPressed))
                if (keyCode == KeyEvent.KEYCODE_ENTER && !multiline) {
                    submit()
                    return@setOnKeyListener true
                }
            }
            false
        }
        input.setOnEditorActionListener { _, actionId, event ->
            if (multiline) return@setOnEditorActionListener false
            if (event == null || event.action == KeyEvent.ACTION_DOWN) {
                if (event == null) owner.host.emit(ViewEvent(id = owner.viewId, type = "keydown", key = "Enter", keyCode = 13, altKey = false, ctrlKey = false, shiftKey = false, metaKey = false))
                submit()
            }
            actionId != EditorInfo.IME_ACTION_NEXT
        }
    }

    private fun submit() {
        val v = input.text.toString()
        if (valueAtFocus != null && valueAtFocus != v) {
            emit("change", v)
            valueAtFocus = v
        }
        emit("submit", v)
    }

    private fun emit(type: String, value: Any?) {
        owner.host.emit(ViewEvent(id = owner.viewId, type = type, value = value))
    }

    /** Apply the props in [patch] (with [all] the merged props). */
    fun apply(all: Map<String, Any?>, patch: Map<String, Any?>) {
        props = all
        val d = owner.density
        fun has(k: String) = patch.containsKey(k)
        val ml = all["multiline"] == true
        if (has("multiline") || has("inputType") || has("readOnly") || ml != multiline) {
            multiline = ml
            inputTypeName = P.str(all["inputType"]) ?: "text"
            readOnly = all["readOnly"] == true
            applyInputType()
        }
        if (has("value")) {
            val v = all["value"]?.let { dev.elpian.core.util.jsString(it) } ?: ""
            if (input.text.toString() != v) {
                suppress = true
                val sel = input.selectionEnd
                input.setText(v)
                input.setSelection(sel.coerceIn(0, v.length))
                suppress = false
                if (focused) valueAtFocus = valueAtFocus ?: v
            }
        }
        if (has("enabled")) {
            input.isEnabled = all["enabled"] != false
            alpha = if (all["enabled"] == false) 0.38f else 1f
        }
        if (has("maxLength")) {
            val n = P.int(all["maxLength"])
            input.filters = if (n != null && n >= 0) arrayOf(InputFilter.LengthFilter(n)) else arrayOf()
        }
        if (multiline && (has("minLines") || has("maxLines"))) {
            P.int(all["maxLines"])?.let { input.maxLines = it } ?: run { input.maxLines = Int.MAX_VALUE }
        }
        if (has("textStyle")) P.textStyle(all["textStyle"])?.let { applyTextStyle(input, it, d) }
        if (has("placeholder") || has("hintStyle") || has("colors")) {
            val hint = P.str(all["placeholder"]) ?: ""
            val hs = P.textStyle(all["hintStyle"])
            val sp = SpannableString(hint)
            if (hs != null && hint.isNotEmpty()) sp.setSpan(HintSpan(hs, d), 0, hint.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            input.hint = sp
            val hc = hs?.color ?: P.color(P.map(all["colors"])?.get("hint")) ?: M3.onSurfaceVariant
            input.setHintTextColor(hc)
        }
        if (has("colors") || has("textStyle")) {
            val colors = P.map(all["colors"]) ?: emptyMap()
            if (P.textStyle(all["textStyle"]) == null) P.color(colors["text"])?.let { input.setTextColor(it) }
            P.color(colors["cursor"])?.let { c ->
                if (Build.VERSION.SDK_INT >= 29) {
                    val g = GradientDrawable()
                    g.setColor(c)
                    g.setSize((2 * d).roundToInt(), 1)
                    input.textCursorDrawable = g
                }
                input.highlightColor = withAlpha(c, 0.4f)
            }
        }
        if (has("suggestions")) {
            val list = P.strings(all["suggestions"])
            if (list.isNotEmpty()) input.setAdapter(ArrayAdapter(context, android.R.layout.simple_dropdown_item_1line, list)) else input.setAdapter(null as ArrayAdapter<String>?)
        }
        if (has("colors") || has("variant") || has("contentPadding") || has("multiline")) applyChrome()
        if (has("autofocus") && all["autofocus"] == true) post { focusAndShowKeyboard() }
        input.gravity = if (multiline) Gravity.TOP or Gravity.START else Gravity.CENTER_VERTICAL or Gravity.START
    }

    private fun applyInputType() {
        var t = when (inputTypeName) {
            "password", "obscure" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            "visiblePassword" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            "email", "emailAddress" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
            "tel", "phone" -> InputType.TYPE_CLASS_PHONE
            "url" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
            "number" -> InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL or InputType.TYPE_NUMBER_FLAG_SIGNED
            "date" -> InputType.TYPE_CLASS_DATETIME or InputType.TYPE_DATETIME_VARIATION_DATE
            "time" -> InputType.TYPE_CLASS_DATETIME or InputType.TYPE_DATETIME_VARIATION_TIME
            "datetime", "datetime-local" -> InputType.TYPE_CLASS_DATETIME
            "name" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PERSON_NAME or InputType.TYPE_TEXT_FLAG_CAP_WORDS
            "search" -> InputType.TYPE_CLASS_TEXT
            "multiline" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            else -> InputType.TYPE_CLASS_TEXT
        }
        if (multiline && (t and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT) t = t or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        val typeface = input.typeface
        input.inputType = t
        input.typeface = typeface
        input.isSingleLine = !multiline
        input.imeOptions = when {
            multiline -> EditorInfo.IME_ACTION_NONE
            inputTypeName == "search" -> EditorInfo.IME_ACTION_SEARCH
            inputTypeName == "url" -> EditorInfo.IME_ACTION_GO
            else -> EditorInfo.IME_ACTION_DONE
        }
        if (readOnly) {
            input.keyListener = null
            input.showSoftInputOnFocus = false
            input.isCursorVisible = false
            input.setTextIsSelectable(true)
        } else {
            input.showSoftInputOnFocus = true
            input.isCursorVisible = true
        }
    }

    private fun applyChrome() {
        val colors = P.map(props["colors"]) ?: emptyMap()
        val focusedWidth = P.num(colors["focusedBorderWidth"]) ?: 2.0
        val width = if (focused) focusedWidth else 1.0
        val cp = P.doubles(props["contentPadding"]) ?: doubleArrayOf(12.0, 12.0, 12.0, 12.0)
        // Keep the text from shifting when the border thickens on focus.
        val inset = width - 1
        val d = owner.density
        fun px(v: Double) = max(0, ((v - inset) * d).roundToInt())
        setPadding(px(cp.getOrElse(3) { 12.0 }) + (width * d).roundToInt(), px(cp.getOrElse(0) { 12.0 }) + (width * d).roundToInt(), px(cp.getOrElse(1) { 12.0 }) + (width * d).roundToInt(), px(cp.getOrElse(2) { 12.0 }) + (width * d).roundToInt())
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val colors = P.map(props["colors"]) ?: emptyMap()
        val d = owner.density
        val radius = ((P.num(colors["radius"]) ?: 4.0) * d).toFloat()
        val border = (if (focused) P.color(colors["focusedBorder"]) ?: P.color(colors["border"]) else P.color(colors["border"]))
        val bw = ((if (focused) P.num(colors["focusedBorderWidth"]) ?: 2.0 else 1.0) * d).toFloat()
        val w = width.toFloat()
        val h = height.toFloat()
        val variant = P.str(props["variant"]) ?: "outline"
        P.color(colors["fill"])?.let { fill ->
            paint.style = Paint.Style.FILL
            paint.color = fill
            if (variant == "underline") {
                val p = Path()
                p.addRoundRect(RectF(0f, 0f, w, h), floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f), Path.Direction.CW)
                canvas.drawPath(p, paint)
            } else canvas.drawRoundRect(RectF(0f, 0f, w, h), radius, radius, paint)
        }
        if (border == null) return
        paint.color = border
        when (variant) {
            "underline" -> {
                paint.style = Paint.Style.FILL
                canvas.drawRect(0f, h - bw, w, h, paint)
            }
            "none" -> {}
            else -> {
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = bw
                canvas.drawRoundRect(RectF(bw / 2, bw / 2, w - bw / 2, h - bw / 2), max(0f, radius - bw / 2), max(0f, radius - bw / 2), paint)
            }
        }
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        input.layout(paddingLeft, paddingTop, right - left - paddingRight, bottom - top - paddingBottom)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val h = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(w, h)
        input.measure(MeasureSpec.makeMeasureSpec(max(0, w - paddingLeft - paddingRight), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(max(0, h - paddingTop - paddingBottom), MeasureSpec.EXACTLY))
    }

    fun focusAndShowKeyboard() {
        input.requestFocus()
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)?.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
    }

    fun blurAndHideKeyboard() {
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)?.hideSoftInputFromWindow(input.windowToken, 0)
        input.clearFocus()
    }

    override fun dispatchSetPressed(pressed: Boolean) {}

}

/**
 * The `select` view kind: a Spinner listing `options` (with optgroup
 * headers, disabled entries and a placeholder), styled from `textStyle`,
 * `colors` and `contentPadding`, with a dropdown arrow.
 */
@SuppressLint("ViewConstructor")
class SelectLeaf(context: Context, private val owner: ElpianView) : FrameLayout(context) {
    private class Entry(val value: String?, val label: String, val header: Boolean, val disabled: Boolean, val placeholder: Boolean)

    private val spinner = Spinner(context, Spinner.MODE_DROPDOWN)
    private var entries: List<Entry> = emptyList()
    private var propValue: String? = null
    private var textStyle: TextStyleSpec? = null
    private var colors: Map<String, Any?> = emptyMap()
    private var padding = doubleArrayOf(0.0, 0.0, 0.0, 0.0)
    private var opened = false
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    private val adapter = object : BaseAdapter() {
        override fun getCount(): Int = entries.size
        override fun getItem(position: Int): Any = entries[position]
        override fun getItemId(position: Int): Long = position.toLong()
        override fun areAllItemsEnabled(): Boolean = false
        override fun isEnabled(position: Int): Boolean = entries.getOrNull(position)?.let { !it.header && !it.disabled && !it.placeholder } ?: false

        private fun style(tv: TextView, e: Entry, dropdown: Boolean) {
            val d = owner.density
            textStyle?.let { applyTextStyle(tv, it, d) } ?: tv.setTextSize(TypedValue.COMPLEX_UNIT_PX, 14 * d)
            P.color(colors["text"])?.let { tv.setTextColor(it) }
            if (e.placeholder) tv.setTextColor(P.color(colors["hint"]) ?: M3.onSurfaceVariant)
            if (e.disabled) tv.alpha = 0.38f else tv.alpha = 1f
            if (e.header) tv.setTypeface(tv.typeface, Typeface.BOLD)
            tv.text = e.label
            tv.isSingleLine = true
            tv.ellipsize = android.text.TextUtils.TruncateAt.END
            tv.gravity = Gravity.CENTER_VERTICAL or Gravity.START
            if (dropdown) {
                val h = (12 * d).roundToInt()
                val indent = if (!e.header && e.value != null && entries.any { it.header }) (16 * d).roundToInt() else 0
                tv.setPadding((16 * d).roundToInt() + indent, h, (16 * d).roundToInt(), h)
                tv.minHeight = (48 * d).roundToInt()
            } else {
                tv.setPadding(0, 0, (24 * d).roundToInt(), 0)
            }
        }

        override fun getView(position: Int, convertView: View?, parent: ViewGroup?): View {
            val tv = (convertView as? TextView) ?: TextView(context)
            entries.getOrNull(position)?.let { style(tv, it, false) }
            tv.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            return tv
        }

        override fun getDropDownView(position: Int, convertView: View?, parent: ViewGroup?): View {
            val tv = (convertView as? TextView) ?: TextView(context)
            entries.getOrNull(position)?.let { style(tv, it, true) }
            return tv
        }
    }

    init {
        setWillNotDraw(false)
        spinner.background = null
        spinner.setPadding(0, 0, 0, 0)
        spinner.adapter = adapter
        addView(spinner, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        spinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val e = entries.getOrNull(position) ?: return
                if (e.header || e.placeholder || e.disabled) return
                if (e.value != propValue) {
                    propValue = e.value
                    emit("change", e.value)
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
        @SuppressLint("ClickableViewAccessibility")
        spinner.setOnTouchListener { _, ev ->
            if (ev.actionMasked == MotionEvent.ACTION_UP && spinner.isEnabled && !opened) {
                opened = true
                emit("focus", null)
            }
            false
        }
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (hasWindowFocus && opened) {
            opened = false
            emit("blur", null)
        }
    }

    private fun emit(type: String, value: Any?) {
        owner.host.emit(ViewEvent(id = owner.viewId, type = type, value = value))
    }

    fun apply(all: Map<String, Any?>, patch: Map<String, Any?>) {
        fun has(k: String) = patch.containsKey(k)
        val d = owner.density
        if (has("textStyle")) textStyle = P.textStyle(all["textStyle"])
        if (has("colors")) {
            colors = P.map(all["colors"]) ?: emptyMap()
            P.color(colors["menu"])?.let { spinner.setPopupBackgroundDrawable(ColorDrawable(it)) }
        }
        if (has("contentPadding")) padding = P.doubles(all["contentPadding"]) ?: doubleArrayOf(0.0, 0.0, 0.0, 0.0)
        setPadding((padding.getOrElse(3) { 0.0 } * d).roundToInt(), (padding.getOrElse(0) { 0.0 } * d).roundToInt(), (padding.getOrElse(1) { 0.0 } * d).roundToInt(), (padding.getOrElse(2) { 0.0 } * d).roundToInt())
        val value = all["value"]?.let { P.str(it) }
        if (has("options") || has("placeholder") || has("value")) {
            val list = ArrayList<Entry>()
            val options = P.list(all["options"]) ?: emptyList()
            val placeholder = P.str(all["placeholder"])
            if (!placeholder.isNullOrEmpty() && options.none { P.str(P.field(it, "value")) == value }) list.add(Entry(null, placeholder, header = false, disabled = true, placeholder = true))
            var group: String? = null
            for (o in options) {
                val g = P.str(P.field(o, "group"))
                if (!g.isNullOrEmpty() && g != group) list.add(Entry(null, g, header = true, disabled = true, placeholder = false))
                group = g
                list.add(Entry(P.str(P.field(o, "value")) ?: "", P.str(P.field(o, "label")) ?: "", header = false, disabled = P.field(o, "disabled") == true, placeholder = false))
            }
            entries = list
            adapter.notifyDataSetChanged()
            propValue = value
            val idx = list.indexOfFirst { !it.header && !it.placeholder && it.value == value }.takeIf { it >= 0 } ?: list.indexOfFirst { it.placeholder }.takeIf { it >= 0 } ?: 0
            if (list.isNotEmpty()) spinner.setSelection(idx, false)
        }
        if (has("enabled")) {
            spinner.isEnabled = all["enabled"] != false
            alpha = if (all["enabled"] == false) 0.38f else 1f
        }
        if (has("textStyle") || has("colors")) adapter.notifyDataSetChanged()
        invalidate()
    }

    fun open() {
        if (spinner.isEnabled) spinner.performClick()
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        // The dropdown arrow (Icons.arrow_drop_down, 24 px) at the end.
        val d = owner.density
        val c = P.color(colors["icon"]) ?: textStyle?.color ?: M3.onSurfaceVariant
        paint.color = c
        paint.style = Paint.Style.FILL
        val cx = width - paddingRight - 12 * d
        val cy = height / 2f
        val p = Path()
        p.moveTo(cx - 5 * d, cy - 2.5f * d)
        p.lineTo(cx + 5 * d, cy - 2.5f * d)
        p.lineTo(cx, cy + 2.5f * d)
        p.close()
        canvas.drawPath(p, paint)
    }

    init {
        setBackgroundColor(Color.TRANSPARENT)
    }
}
