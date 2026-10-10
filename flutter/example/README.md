# elpian_ui_example

The Flutter host's demo app: one screen per example in `lib/examples/`
(landing page, canvas, JSON stylesheets, QuickJS calculator and whiteboard,
`Scene3D`, the VM, the showcase, …).

```sh
flutter run -d chrome                                    # lib/main.dart: the 2D example picker on web
flutter run -t lib/examples/landing_page_example.dart    # one example directly
```

The same mini apps run without Flutter on the native hosts in
[`../../native/`](../../native/) — see
[`../../wiki/23-native-hosts.md`](../../wiki/23-native-hosts.md).
