import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/node_events.dart';
import '../models/elpian_node.dart';
import '../css/css_parser.dart';
import '../css/css_properties.dart';
import 'html_details.dart';

/// `<dialog>`.
///
/// Closed (renders nothing) unless the `open` attribute is present. Open
/// and non-modal it is a card in the flow of the page. With `modal` (as
/// after `showModal()`) it is shown above the whole app in the overlay,
/// centred over a backdrop (`props.backdropColor`, default 54% black) that
/// blocks the page beneath.
///
/// Closing: `closedby` = `any` (the backdrop and Escape close it),
/// `closerequest` (Escape only — the default for a modal dialog) or `none`
/// (the default for a non-modal one). A close request dispatches `cancel`,
/// then the dialog closes itself and dispatches `close`. It stays closed
/// until a render sets `open` again after having cleared it, or changes it.
class HtmlDialog {
  static Widget build(ElpianNode node, List<Widget> children) {
    return _HtmlDialog(
      key: node.key != null ? ValueKey<String>('dialog_${node.key}') : null,
      node: node,
      events: NodeEvents(node),
      children: children,
    );
  }

  static bool isModal(ElpianNode node) =>
      HtmlDetails.isOpen(node.props['modal']) ||
      node.props['showModal'] == true;
}

class _HtmlDialog extends StatefulWidget {
  const _HtmlDialog({
    super.key,
    required this.node,
    required this.children,
    required this.events,
  });

  final ElpianNode node;
  final List<Widget> children;
  final NodeEvents events;

  @override
  State<_HtmlDialog> createState() => _HtmlDialogState();
}

class _HtmlDialogState extends State<_HtmlDialog> {
  final OverlayPortalController _portal = OverlayPortalController();
  bool _closedLocally = false;

  @override
  void initState() {
    super.initState();
    // The portal is only in the tree while the dialog is open and modal, so
    // it can simply always be "showing".
    _portal.show();
  }

  bool get _openAttr => HtmlDetails.isOpen(widget.node.props['open']);
  bool get _open => _openAttr && !_closedLocally;
  bool get _modal => HtmlDialog.isModal(widget.node);

  String get _closedBy {
    final v = widget.node.props['closedby'] ?? widget.node.props['closedBy'];
    if (v is String && const {'any', 'closerequest', 'none'}.contains(v)) {
      return v;
    }
    return _modal ? 'closerequest' : 'none';
  }

  @override
  void didUpdateWidget(covariant _HtmlDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = HtmlDetails.isOpen(oldWidget.node.props['open']);
    // Re-opened (or explicitly closed) by the page: its word wins again.
    if (was != _openAttr) _closedLocally = false;
  }

  void _requestClose({required bool fromBackdrop}) {
    final closedBy = _closedBy;
    if (closedBy == 'none' || (fromBackdrop && closedBy != 'any')) return;
    widget.events.emit('cancel');
    setState(() => _closedLocally = true);
    widget.events.emit('close');
  }

  Widget _card(BuildContext context) {
    final style = widget.node.style;
    final radius = style?.borderRadius ?? BorderRadius.circular(28);
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((widget.node.props['text']?.toString() ?? '').isNotEmpty)
          Text(widget.node.props['text'].toString()),
        ...widget.children,
      ],
    );
    content = Padding(
      padding: style?.padding ?? const EdgeInsets.all(24),
      child: content,
    );
    if (style != null) content = CSSProperties.applyStyle(content, style);

    return Semantics(
      scopesRoute: _modal,
      namesRoute: _modal,
      explicitChildNodes: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
        child: Material(
          color: style?.backgroundColor ??
              Theme.of(context).colorScheme.surfaceContainerHigh,
          elevation: 6,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      ),
    );
  }

  Widget _closable(Widget child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _requestClose(fromBackdrop: false),
        },
        child: Focus(autofocus: true, child: child),
      );

  @override
  Widget build(BuildContext context) {
    if (!_open) return const SizedBox.shrink();

    if (!_modal) return _closable(_card(context));

    final barrierColor =
        CSSParser.parseColor(widget.node.props['backdropColor']) ??
            (widget.node.props['backdropColor'] is int
                ? Color(widget.node.props['backdropColor'] as int)
                : Colors.black54);

    Widget modal(BuildContext context) => Stack(
          children: [
            Positioned.fill(
              child: ModalBarrier(
                color: barrierColor,
                dismissible: _closedBy == 'any',
                onDismiss: () => _requestClose(fromBackdrop: true),
              ),
            ),
            Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                child: _closable(_card(context)),
              ),
            ),
          ],
        );

    // No overlay to float in (e.g. rendered outside any Navigator): cover
    // the space the dialog was given instead.
    if (Overlay.maybeOf(context) == null) return modal(context);

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: modal,
      child: const SizedBox.shrink(),
    );
  }
}
