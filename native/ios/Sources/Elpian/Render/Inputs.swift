#if canImport(UIKit)
import UIKit
#if !ELPIAN_SINGLE_MODULE
import ElpianCore
#endif

/** The font and colour of a [TextStyleSpec] for native text controls. */
func uiFont(_ s: TextStyleSpec) -> UIFont { ElpianFonts.font(s.fontFamily, s.fontWeight, s.italic, CGFloat(s.fontSize)) }

func textAttributes(_ s: TextStyleSpec) -> [NSAttributedString.Key: Any] {
    var a: [NSAttributedString.Key: Any] = [.font: uiFont(s), .foregroundColor: Paints.uiColor(s.color), .kern: s.letterSpacing]
    if s.decoration & 1 != 0 { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
    if s.decoration & 4 != 0 { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    if let h = s.height, h > 0 {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = CGFloat(h * s.fontSize)
        p.maximumLineHeight = CGFloat(h * s.fontSize)
        a[.paragraphStyle] = p
    }
    return a
}

/**
 * The `textInput` view kind (Inputs.kt): a UITextField (single line) or
 * UITextView (multiline) inside Material chrome — outline / underline / none,
 * fill, radius, a border that thickens on focus without shifting the text —
 * with an autocomplete list for `suggestions` (datalist).
 */
final class TextInputLeaf: UIView, UITextFieldDelegate, UITextViewDelegate {
    private weak var owner: ElpianView?
    private let field = UITextField()
    private let area = UITextView()
    private let placeholderLabel = UILabel()
    private var props = JSONObject()
    private var suppress = false
    private(set) var focused = false
    private var valueAtFocus: String?
    private var multiline = false
    private var inputTypeName = "text"
    private var readOnly = false
    private var maxLength: Int?
    private var suggestions: [String] = []
    private var dropdown: SuggestionList?

    init(owner: ElpianView) {
        self.owner = owner
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        field.borderStyle = .none
        field.textColor = Paints.uiColor(M3.onSurface)
        field.delegate = self
        field.addTarget(self, action: #selector(fieldChanged), for: .editingChanged)
        area.backgroundColor = .clear
        area.textContainerInset = .zero
        area.textContainer.lineFragmentPadding = 0
        area.textColor = Paints.uiColor(M3.onSurface)
        area.delegate = self
        area.isHidden = true
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isHidden = true
        addSubview(field)
        addSubview(area)
        area.addSubview(placeholderLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var input: UIView { multiline ? area : field }

    private var text: String {
        get { multiline ? (area.text ?? "") : (field.text ?? "") }
        set {
            if multiline { area.text = newValue } else { field.text = newValue }
            updatePlaceholder()
        }
    }

    private func emit(_ type: String, _ value: Any?) {
        guard let o = owner else { return }
        o.host?.emit(ViewEvent(id: o.viewId, type: type, value: value))
    }

    private func emitKey(_ key: String, _ code: Int) {
        guard let o = owner else { return }
        o.host?.emit(ViewEvent(id: o.viewId, type: "keydown", key: key, keyCode: code, altKey: false, ctrlKey: false, shiftKey: false, metaKey: false))
    }

    // ---------------------------------------------------------------------
    // Props
    // ---------------------------------------------------------------------

    /** Apply the props in [patch] (with [all] the merged props). */
    func apply(_ all: JSONObject, _ patch: JSONObject) {
        props = all
        func has(_ k: String) -> Bool { patch.has(k) }
        let ml = HostProps.bool(all["multiline"])
        if has("multiline") || has("inputType") || has("readOnly") || ml != multiline {
            let current = text
            multiline = ml
            inputTypeName = HostProps.str(all["inputType"]) ?? "text"
            readOnly = HostProps.bool(all["readOnly"])
            field.isHidden = multiline
            area.isHidden = !multiline
            text = current
            applyInputType()
        }
        if has("value") {
            let v = flattenOptional(all["value"]).map { jsString($0) } ?? ""
            if text != v {
                suppress = true
                text = v
                suppress = false
                if focused && valueAtFocus == nil { valueAtFocus = v }
            }
        }
        if has("enabled") {
            let en = !HostProps.isFalse(all["enabled"])
            field.isEnabled = en
            area.isEditable = en && !readOnly
            area.isSelectable = en
            alpha = en ? 1 : 0.38
        }
        if has("maxLength") {
            let n = HostProps.int(all["maxLength"])
            maxLength = n.flatMap { $0 >= 0 ? $0 : nil }
        }
        if multiline && (has("minLines") || has("maxLines")) {
            area.textContainer.maximumNumberOfLines = 0
        }
        if has("textStyle"), let ts = HostProps.textStyle(all["textStyle"]) {
            let attrs = textAttributes(ts)
            field.defaultTextAttributes = attrs
            area.typingAttributes = attrs
            area.font = uiFont(ts)
            area.textColor = Paints.uiColor(ts.color)
            area.attributedText = NSAttributedString(string: area.text ?? "", attributes: attrs)
        }
        if has("placeholder") || has("hintStyle") || has("colors") || has("textStyle") {
            let hint = HostProps.str(all["placeholder"]) ?? ""
            let hs = HostProps.textStyle(all["hintStyle"])
            let colors = HostProps.map(all["colors"]) ?? JSONObject()
            let hc = hs?.color ?? HostProps.color(colors["hint"]) ?? M3.onSurfaceVariant
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: Paints.uiColor(hc)]
            if let hs = hs { attrs[.font] = uiFont(hs) } else if let ts = HostProps.textStyle(all["textStyle"]) { attrs[.font] = uiFont(ts) }
            field.attributedPlaceholder = NSAttributedString(string: hint, attributes: attrs)
            placeholderLabel.attributedText = NSAttributedString(string: hint, attributes: attrs)
            updatePlaceholder()
        }
        if has("colors") || has("textStyle") {
            let colors = HostProps.map(all["colors"]) ?? JSONObject()
            if HostProps.textStyle(all["textStyle"]) == nil, let c = HostProps.color(colors["text"]) {
                field.textColor = Paints.uiColor(c)
                area.textColor = Paints.uiColor(c)
            }
            if let c = HostProps.color(colors["cursor"]) {
                field.tintColor = Paints.uiColor(c)
                area.tintColor = Paints.uiColor(c)
            }
        }
        if has("suggestions") {
            suggestions = HostProps.strings(all["suggestions"])
            if suggestions.isEmpty { hideSuggestions() }
        }
        if has("colors") || has("variant") || has("contentPadding") || has("multiline") { applyChrome() }
        if has("autofocus") && HostProps.bool(all["autofocus"]) {
            DispatchQueue.main.async { [weak self] in self?.focusAndShowKeyboard() }
        }
    }

    private func applyInputType() {
        var kb: UIKeyboardType = .default
        var content: UITextContentType?
        var secure = false
        var cap: UITextAutocapitalizationType = .sentences
        var correction: UITextAutocorrectionType = .default
        switch inputTypeName {
        case "password", "obscure": secure = true; content = .password; cap = .none; correction = .no
        case "visiblePassword": content = .password; cap = .none; correction = .no
        case "email", "emailAddress": kb = .emailAddress; content = .emailAddress; cap = .none; correction = .no
        case "tel", "phone": kb = .phonePad; content = .telephoneNumber
        case "url": kb = .URL; content = .URL; cap = .none; correction = .no
        case "number": kb = .decimalPad
        case "date", "time", "datetime", "datetime-local": kb = .numbersAndPunctuation
        case "name": content = .name; cap = .words
        case "search": kb = .webSearch
        default: break
        }
        field.keyboardType = kb
        field.textContentType = content
        field.isSecureTextEntry = secure
        field.autocapitalizationType = cap
        field.autocorrectionType = correction
        field.returnKeyType = inputTypeName == "search" ? .search : (inputTypeName == "url" ? .go : .done)
        area.keyboardType = kb
        area.autocapitalizationType = cap
        area.autocorrectionType = correction
        area.isEditable = !readOnly
        area.isSelectable = true
    }

    private func applyChrome() {
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let colors = HostProps.map(props["colors"]) ?? JSONObject()
        let focusedWidth = HostProps.num(colors["focusedBorderWidth"]) ?? 2
        let width = focused ? focusedWidth : 1
        let cp = HostProps.doubles(props["contentPadding"]) ?? [12, 12, 12, 12]
        func at(_ i: Int) -> Double { i < cp.count ? cp[i] : 12 }
        // Keep the text from shifting when the border thickens on focus.
        let inset = width - 1
        func px(_ v: Double) -> CGFloat { CGFloat(max(0, v - inset) + width) }
        let r = bounds.inset(by: UIEdgeInsets(top: px(at(0)), left: px(at(3)), bottom: px(at(2)), right: px(at(1))))
        field.frame = r
        area.frame = r
        placeholderLabel.frame = CGRect(x: 0, y: 0, width: r.width, height: placeholderLabel.sizeThatFits(CGSize(width: r.width, height: .greatestFiniteMagnitude)).height)
        dropdown?.reposition()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let colors = HostProps.map(props["colors"]) ?? JSONObject()
        let radius = CGFloat(HostProps.num(colors["radius"]) ?? 4)
        let border = focused ? (HostProps.color(colors["focusedBorder"]) ?? HostProps.color(colors["border"])) : HostProps.color(colors["border"])
        let bw = CGFloat(focused ? (HostProps.num(colors["focusedBorderWidth"]) ?? 2) : 1)
        let w = bounds.width, h = bounds.height
        let variant = HostProps.str(props["variant"]) ?? "outline"
        if let f = HostProps.color(colors["fill"]) {
            ctx.setFillColor(Paints.cgColor(f))
            if variant == "underline" {
                let p = CGMutablePath()
                Paints.addRoundRect(p, bounds, [Double(radius), Double(radius), Double(radius), Double(radius), 0, 0, 0, 0])
                ctx.addPath(p)
            } else {
                ctx.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath)
            }
            ctx.fillPath()
        }
        guard let b = border else { return }
        switch variant {
        case "underline":
            ctx.setFillColor(Paints.cgColor(b))
            ctx.fill(CGRect(x: 0, y: h - bw, width: w, height: bw))
        case "none":
            break
        default:
            ctx.setStrokeColor(Paints.cgColor(b))
            ctx.setLineWidth(bw)
            ctx.addPath(UIBezierPath(roundedRect: CGRect(x: bw / 2, y: bw / 2, width: w - bw, height: h - bw), cornerRadius: max(0, radius - bw / 2)).cgPath)
            ctx.strokePath()
        }
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !multiline || !(area.text ?? "").isEmpty
    }

    // ---------------------------------------------------------------------
    // Editing
    // ---------------------------------------------------------------------

    private func changed() {
        updatePlaceholder()
        if !suppress { emit("input", text) }
        updateSuggestions()
    }

    @objc private func fieldChanged() { changed() }

    func textViewDidChange(_ textView: UITextView) { changed() }

    private func began() {
        focused = true
        valueAtFocus = text
        applyChrome()
        emit("focus", nil)
        updateSuggestions()
    }

    private func ended() {
        focused = false
        applyChrome()
        let v = text
        if let f = valueAtFocus, f != v { emit("change", v) }
        valueAtFocus = nil
        hideSuggestions()
        emit("blur", nil)
    }

        func textFieldDidBeginEditing(_ textField: UITextField) { began() }
    func textFieldDidEndEditing(_ textField: UITextField) { ended() }
    func textViewDidBeginEditing(_ textView: UITextView) { began() }
    func textViewDidEndEditing(_ textView: UITextView) { ended() }

    private func allowed(_ current: String, _ range: NSRange, _ replacement: String) -> Bool {
        if readOnly { return false }
        guard let n = maxLength else { return true }
        let next = (current as NSString).replacingCharacters(in: range, with: replacement)
        return (next as NSString).length <= n || (next as NSString).length < (current as NSString).length
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        allowed(textField.text ?? "", range, string)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        allowed(textView.text ?? "", range, text)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        emitKey("Enter", 13)
        submit()
        if field.returnKeyType != .next { field.resignFirstResponder() }
        return false
    }

    private func submit() {
        let v = text
        if let f = valueAtFocus, f != v {
            emit("change", v)
            valueAtFocus = v
        }
        emit("submit", v)
    }

    func focusAndShowKeyboard() { _ = input.becomeFirstResponder() }

    func blurAndHideKeyboard() { _ = input.resignFirstResponder() }

    func selectAll() {
        if multiline { area.selectAll(nil) } else { field.selectAll(nil) }
    }

    // ---------------------------------------------------------------------
    // Suggestions (datalist)
    // ---------------------------------------------------------------------

    private func updateSuggestions() {
        guard focused, !suggestions.isEmpty else {
            hideSuggestions()
            return
        }
        let q = text.lowercased()
        let matches = q.isEmpty ? [] : suggestions.filter { $0.lowercased().contains(q) && $0 != text }
        if matches.isEmpty {
            hideSuggestions()
            return
        }
        let d = dropdown ?? SuggestionList(anchor: self) { [weak self] picked in
            guard let self = self else { return }
            self.text = picked
            self.changed()
            self.hideSuggestions()
        }
        dropdown = d
        d.show(matches)
    }

    private func hideSuggestions() {
        dropdown?.dismiss()
        dropdown = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { hideSuggestions() }
    }
}

/** The autocomplete dropdown under a text input (AutoCompleteTextView's list). */
final class SuggestionList: NSObject, UITableViewDataSource, UITableViewDelegate {
    private weak var anchor: UIView?
    private let table = UITableView(frame: .zero, style: .plain)
    private var items: [String] = []
    private let pick: (String) -> Void

    init(anchor: UIView, pick: @escaping (String) -> Void) {
        self.anchor = anchor
        self.pick = pick
        super.init()
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 44
        table.layer.cornerRadius = 4
        table.layer.shadowOpacity = 0.2
        table.layer.shadowRadius = 4
        table.clipsToBounds = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: "s")
    }

    func show(_ list: [String]) {
        items = list
        table.reloadData()
        guard let a = anchor, let w = a.window else { return }
        if table.superview !== w { w.addSubview(table) }
        reposition()
    }

    func reposition() {
        guard let a = anchor, let w = a.window else { return }
        let r = a.convert(a.bounds, to: w)
        let h = min(CGFloat(items.count) * 44, 220)
        table.frame = CGRect(x: r.minX, y: r.maxY, width: r.width, height: h)
    }

    func dismiss() { table.removeFromSuperview() }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "s", for: indexPath)
        var cfg = cell.defaultContentConfiguration()
        cfg.text = items[indexPath.row]
        cell.contentConfiguration = cfg
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        pick(items[indexPath.row])
    }
}

/**
 * The `select` view kind (SelectLeaf in Inputs.kt): a button showing the
 * selected option that opens a UIMenu listing `options` (with optgroup
 * sections, disabled entries and a placeholder), styled from `textStyle`,
 * `colors` and `contentPadding`, with a dropdown arrow. The `open` / `focus`
 * commands present the same list as an action sheet (a UIMenu cannot be
 * opened programmatically).
 */
final class SelectLeaf: UIView {
    private struct Entry {
        let value: String?
        let label: String
        let header: Bool
        let disabled: Bool
        let placeholder: Bool
        let group: String?
    }

    private weak var owner: ElpianView?
    private let button = UIButton(type: .custom)
    private var entries: [Entry] = []
    private var propValue: String?
    private var textStyle: TextStyleSpec?
    private var colors = JSONObject()
    private var padding: [Double] = [0, 0, 0, 0]
    private var enabled = true
    private var opened = false

    init(owner: ElpianView) {
        self.owner = owner
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.showsMenuAsPrimaryAction = true
        button.addTarget(self, action: #selector(menuOpened), for: .menuActionTriggered)
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func emit(_ type: String, _ value: Any?) {
        guard let o = owner else { return }
        o.host?.emit(ViewEvent(id: o.viewId, type: type, value: value))
    }

    @objc private func menuOpened() {
        if !opened {
            opened = true
            emit("focus", nil)
        }
    }

    func apply(_ all: JSONObject, _ patch: JSONObject) {
        func has(_ k: String) -> Bool { patch.has(k) }
        if has("textStyle") { textStyle = HostProps.textStyle(all["textStyle"]) }
        if has("colors") { colors = HostProps.map(all["colors"]) ?? JSONObject() }
        if has("contentPadding") { padding = HostProps.doubles(all["contentPadding"]) ?? [0, 0, 0, 0] }
        let value = flattenOptional(all["value"]).flatMap { HostProps.str($0) }
        if has("options") || has("placeholder") || has("value") {
            var list: [Entry] = []
            let options = HostProps.list(all["options"]) ?? []
            let placeholder = HostProps.str(all["placeholder"])
            if let ph = placeholder, !ph.isEmpty, !options.contains(where: { HostProps.str(HostProps.field($0, "value")) == value }) {
                list.append(Entry(value: nil, label: ph, header: false, disabled: true, placeholder: true, group: nil))
            }
            var group: String?
            for o in options {
                let g = HostProps.str(HostProps.field(o, "group"))
                if let g = g, !g.isEmpty, g != group { list.append(Entry(value: nil, label: g, header: true, disabled: true, placeholder: false, group: g)) }
                group = g
                list.append(Entry(value: HostProps.str(HostProps.field(o, "value")) ?? "", label: HostProps.str(HostProps.field(o, "label")) ?? "", header: false,
                                  disabled: HostProps.bool(HostProps.field(o, "disabled")), placeholder: false, group: g))
            }
            entries = list
            propValue = value
        }
        if has("enabled") {
            enabled = !HostProps.isFalse(all["enabled"])
            button.isEnabled = enabled
            alpha = enabled ? 1 : 0.38
        }
        rebuild()
        setNeedsLayout()
        setNeedsDisplay()
    }

    private func titleEntry() -> Entry? {
        entries.first { !$0.header && !$0.placeholder && $0.value == propValue } ?? entries.first { $0.placeholder } ?? entries.first { !$0.header }
    }

    private func rebuild() {
        let shown = titleEntry()
        var attrs: [NSAttributedString.Key: Any] = textStyle.map { textAttributes($0) } ?? [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: Paints.uiColor(M3.onSurface)]
        if let c = HostProps.color(colors["text"]) { attrs[.foregroundColor] = Paints.uiColor(c) }
        if shown?.placeholder == true { attrs[.foregroundColor] = Paints.uiColor(HostProps.color(colors["hint"]) ?? M3.onSurfaceVariant) }
        button.setAttributedTitle(NSAttributedString(string: shown?.label ?? "", attributes: attrs), for: .normal)
        // The menu: optgroups as inline sections.
        var children: [UIMenuElement] = []
        var section: [UIMenuElement] = []
        var sectionTitle: String?
        func flush() {
            if let t = sectionTitle {
                children.append(UIMenu(title: t, options: .displayInline, children: section))
            } else {
                children.append(contentsOf: section)
            }
            section = []
        }
        for e in entries where !e.placeholder {
            if e.header {
                flush()
                sectionTitle = e.label
                continue
            }
            let action = UIAction(title: e.label, attributes: e.disabled ? [.disabled] : [], state: e.value == propValue ? .on : .off) { [weak self] _ in
                self?.choose(e.value)
            }
            section.append(action)
        }
        flush()
        button.menu = UIMenu(title: "", children: children)
    }

    private func choose(_ value: String?) {
        if value != propValue {
            propValue = value
            rebuild()
            emit("change", value)
        }
        if opened {
            opened = false
            emit("blur", nil)
        }
    }

    /** The `open` command: the options as an action sheet. */
    func open() {
        guard enabled, let vc = owner?.window?.rootViewController else { return }
        var top = vc
        while let p = top.presentedViewController { top = p }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for e in entries where !e.placeholder {
            if e.header {
                let h = UIAlertAction(title: e.label, style: .default, handler: nil)
                h.isEnabled = false
                sheet.addAction(h)
                continue
            }
            let title = e.value == propValue ? "\u{2713} " + e.label : e.label
            let a = UIAlertAction(title: title, style: .default) { [weak self] _ in self?.choose(e.value) }
            a.isEnabled = !e.disabled
            sheet.addAction(a)
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            guard let self = self, self.opened else { return }
            self.opened = false
            self.emit("blur", nil)
        })
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = self
            pop.sourceRect = bounds
        }
        opened = true
        emit("focus", nil)
        top.present(sheet, animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        func at(_ i: Int) -> CGFloat { i < padding.count ? CGFloat(padding[i]) : 0 }
        button.frame = bounds.inset(by: UIEdgeInsets(top: at(0), left: at(3), bottom: at(2), right: at(1)))
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 24)
    }

    override func draw(_ rect: CGRect) {
        // The dropdown arrow (Icons.arrow_drop_down, 24 px) at the end.
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let c = HostProps.color(colors["icon"]) ?? textStyle?.color ?? M3.onSurfaceVariant
        let right = padding.count > 1 ? CGFloat(padding[1]) : 0
        let cx = bounds.width - right - 12
        let cy = bounds.midY
        ctx.setFillColor(Paints.cgColor(c))
        ctx.move(to: CGPoint(x: cx - 5, y: cy - 2.5))
        ctx.addLine(to: CGPoint(x: cx + 5, y: cy - 2.5))
        ctx.addLine(to: CGPoint(x: cx, y: cy + 2.5))
        ctx.closePath()
        ctx.fillPath()
    }
}
#endif
