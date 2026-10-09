import 'package:flutter/material.dart';
import '../models/elpian_node.dart';
import '../css/css_properties.dart';

class ElpianIcon {
  static Widget build(ElpianNode node, List<Widget> children) {
    final iconName = node.props['icon'] as String? ?? 'star';
    final size = node.style?.fontSize ?? node.props['size'] as double? ?? 24.0;
    final color = node.style?.color;

    Widget result = Icon(
      _getIcon(iconName),
      size: size,
      color: color,
    );

    if (node.style != null) {
      result = CSSProperties.applyStyle(result, node.style);
    }

    return result;
  }

  static IconData _getIcon(String name) {
    return _iconMap[name.toLowerCase()] ?? Icons.star;
  }

  static final Map<String, IconData> _iconMap = {
    // Navigation
    'arrow_back': Icons.arrow_back,
    'arrow_forward': Icons.arrow_forward,
    'arrow_upward': Icons.arrow_upward,
    'arrow_downward': Icons.arrow_downward,
    'chevron_left': Icons.chevron_left,
    'chevron_right': Icons.chevron_right,
    'expand_more': Icons.expand_more,
    'expand_less': Icons.expand_less,
    'menu': Icons.menu,
    'close': Icons.close,
    'more_vert': Icons.more_vert,
    'more_horiz': Icons.more_horiz,
    // Actions
    'search': Icons.search,
    'home': Icons.home,
    'settings': Icons.settings,
    'favorite': Icons.favorite,
    'favorite_border': Icons.favorite_border,
    'star': Icons.star,
    'star_border': Icons.star_border,
    'star_half': Icons.star_half,
    'add': Icons.add,
    'remove': Icons.remove,
    'delete': Icons.delete,
    'edit': Icons.edit,
    'share': Icons.share,
    'check': Icons.check,
    'check_circle': Icons.check_circle,
    'check_circle_outline': Icons.check_circle_outline,
    'done': Icons.done,
    'done_all': Icons.done_all,
    'thumb_up': Icons.thumb_up,
    'thumb_down': Icons.thumb_down,
    'visibility': Icons.visibility,
    'visibility_off': Icons.visibility_off,
    'lock': Icons.lock,
    'lock_open': Icons.lock_open,
    'bookmark': Icons.bookmark,
    'bookmark_border': Icons.bookmark_border,
    'copy': Icons.copy,
    'download': Icons.download,
    'upload': Icons.upload,
    'refresh': Icons.refresh,
    'sync': Icons.sync,
    // Communication
    'email': Icons.email,
    'phone': Icons.phone,
    'message': Icons.message,
    'chat': Icons.chat,
    'send': Icons.send,
    'notifications': Icons.notifications,
    'notifications_none': Icons.notifications_none,
    // Content
    'add_circle': Icons.add_circle,
    'add_circle_outline': Icons.add_circle_outline,
    'remove_circle': Icons.remove_circle,
    'flag': Icons.flag,
    'link': Icons.link,
    'sort': Icons.sort,
    'filter_list': Icons.filter_list,
    // Social
    'person': Icons.person,
    'person_outline': Icons.person_outline,
    'people': Icons.people,
    'group': Icons.group,
    'public': Icons.public,
    // Alert
    'error': Icons.error,
    'error_outline': Icons.error_outline,
    'warning': Icons.warning,
    'info': Icons.info,
    'info_outline': Icons.info_outline,
    'help': Icons.help,
    'help_outline': Icons.help_outline,
    // AV
    'play_arrow': Icons.play_arrow,
    'pause': Icons.pause,
    'stop': Icons.stop,
    'volume_up': Icons.volume_up,
    'volume_off': Icons.volume_off,
    // File
    'folder': Icons.folder,
    'folder_open': Icons.folder_open,
    'attach_file': Icons.attach_file,
    'cloud': Icons.cloud,
    'cloud_upload': Icons.cloud_upload,
    'cloud_download': Icons.cloud_download,
    // Device
    'smartphone': Icons.smartphone,
    'computer': Icons.computer,
    'tablet': Icons.tablet,
    'wifi': Icons.wifi,
    'bluetooth': Icons.bluetooth,
    'battery_full': Icons.battery_full,
    'brightness_high': Icons.brightness_high,
    // Places
    'location_on': Icons.location_on,
    'place': Icons.place,
    'map': Icons.map,
    'local_offer': Icons.local_offer,
    'restaurant': Icons.restaurant,
    // Business
    'work': Icons.work,
    'business': Icons.business,
    'dashboard': Icons.dashboard,
    'analytics': Icons.analytics,
    'trending_up': Icons.trending_up,
    'trending_down': Icons.trending_down,
    'trending_flat': Icons.trending_flat,
    'account_balance': Icons.account_balance,
    'shopping_cart': Icons.shopping_cart,
    'payment': Icons.payment,
    'receipt': Icons.receipt,
    'attach_money': Icons.attach_money,
    // UI
    'apps': Icons.apps,
    'grid_view': Icons.grid_view,
    'view_list': Icons.view_list,
    'calendar_today': Icons.calendar_today,
    'schedule': Icons.schedule,
    'access_time': Icons.access_time,
    'timer': Icons.timer,
    // Misc
    'light_mode': Icons.light_mode,
    'dark_mode': Icons.dark_mode,
    'language': Icons.language,
    'code': Icons.code,
    'terminal': Icons.terminal,
    'bug_report': Icons.bug_report,
    'build': Icons.build,
    'extension': Icons.extension,
    'rocket_launch': Icons.rocket_launch,
    'speed': Icons.speed,
    'shield': Icons.shield,
    'verified': Icons.verified,
    'auto_awesome': Icons.auto_awesome,
    'touch_app': Icons.touch_app,
    'bolt': Icons.bolt,
    'eco': Icons.eco,
    'palette': Icons.palette,
    'brush': Icons.brush,
    'photo': Icons.photo,
    'camera': Icons.camera,
    'image': Icons.image,
  };
}
