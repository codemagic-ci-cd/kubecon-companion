import 'dart:js_interop';

@JS('plausible')
external JSFunction? get _plausible;

@JS('plausible')
external void _send(String event, JSAny options);

/// Sends a custom event when the Plausible script (or its queue stub in
/// index.html) is on the page.
void track(String event, Map<String, String> props) {
  if (_plausible == null) return;
  _send(event, {'props': props}.jsify()!);
}
