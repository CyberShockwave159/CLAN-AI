import 'package:web/web.dart' as web;

/// Hard-reloads the current page so the freshly deployed release boots.
void reloadAppPage() {
  web.window.location.reload();
}