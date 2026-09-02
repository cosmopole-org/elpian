/// Every HTML element builder Elpian registers.
///
/// An internal barrel: `src/` files import this instead of the package's own
/// public entrypoint, so nothing inside the library depends on its own public
/// API. Not exported from `elpian_ui.dart` directly — the public barrel lists
/// these individually so the documented surface stays explicit.
library;

// `html_embedded_content_{io,stub}.dart` are deliberately absent: they are a
// conditional-import pair resolved at their single consumer, and exporting both
// would make `HtmlEmbeddedContent` ambiguous.

export 'html_a.dart';
export 'html_abbr.dart';
export 'html_area.dart';
export 'html_article.dart';
export 'html_aside.dart';
export 'html_audio.dart';
export 'html_blockquote.dart';
export 'html_br.dart';
export 'html_button.dart';
export 'html_canvas.dart';
export 'html_cite.dart';
export 'html_code.dart';
export 'html_data.dart';
export 'html_datalist.dart';
export 'html_del.dart';
export 'html_details.dart';
export 'html_dialog.dart';
export 'html_div.dart';
export 'html_em.dart';
export 'html_embed.dart';
export 'html_embedded_content.dart';
export 'html_fieldset.dart';
export 'html_figcaption.dart';
export 'html_figure.dart';
export 'html_footer.dart';
export 'html_form.dart';
export 'html_h1.dart';
export 'html_h2.dart';
export 'html_h3.dart';
export 'html_h4.dart';
export 'html_h5.dart';
export 'html_h6.dart';
export 'html_header.dart';
export 'html_hr.dart';
export 'html_iframe.dart';
export 'html_img.dart';
export 'html_input.dart';
export 'html_ins.dart';
export 'html_kbd.dart';
export 'html_label.dart';
export 'html_legend.dart';
export 'html_li.dart';
export 'html_main.dart';
export 'html_map.dart';
export 'html_mark.dart';
export 'html_meter.dart';
export 'html_nav.dart';
export 'html_object.dart';
export 'html_ol.dart';
export 'html_optgroup.dart';
export 'html_option.dart';
export 'html_output.dart';
export 'html_p.dart';
export 'html_param.dart';
export 'html_picture.dart';
export 'html_pre.dart';
export 'html_progress.dart';
export 'html_samp.dart';
export 'html_section.dart';
export 'html_select.dart';
export 'html_small.dart';
export 'html_source.dart';
export 'html_span.dart';
export 'html_strong.dart';
export 'html_sub.dart';
export 'html_summary.dart';
export 'html_sup.dart';
export 'html_table.dart';
export 'html_td.dart';
export 'html_textarea.dart';
export 'html_th.dart';
export 'html_time.dart';
export 'html_tr.dart';
export 'html_track.dart';
export 'html_ul.dart';
export 'html_var.dart';
export 'html_video.dart';
