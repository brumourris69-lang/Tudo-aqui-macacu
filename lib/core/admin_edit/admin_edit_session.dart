import 'package:flutter/foundation.dart';

/// Interaction state only. Authorization is supplied by the existing UI gate;
/// this does not grant permissions to write data.
class AdminEditSession extends ChangeNotifier {
  bool _authorized = false;
  bool _active = false;
  bool _preview = false;
  bool _dirty = false;

  bool get authorized => _authorized;
  bool get active => _active;
  bool get preview => _preview;
  bool get dirty => _dirty;

  void setAuthorized(bool value) {
    if (_authorized == value) return;
    _authorized = value;
    if (!value) _clear();
    notifyListeners();
  }

  void activate() {
    if (!_authorized || _active) return;
    _active = true;
    notifyListeners();
  }

  void setDirty(bool value) {
    if (!_active || _dirty == value) return;
    _dirty = value;
    notifyListeners();
  }

  void togglePreview() {
    if (!_active) return;
    _preview = !_preview;
    notifyListeners();
  }

  void reset() {
    if (!_active && !_preview && !_dirty) return;
    _clear();
    notifyListeners();
  }

  void _clear() {
    _active = false;
    _preview = false;
    _dirty = false;
  }
}
