import 'dart:js_interop';

@JS('dgAnalytics')
external _DgAnalytics? get _dgAnalytics;

extension type _DgAnalytics._(JSObject _) implements JSObject {
  external bool get enabled;
  external JSString? consent();
  external void setConsent(bool granted);
}

/// Whether Tag Manager is configured for this site (GTM_ID at build time).
bool get analyticsAvailable => _dgAnalytics?.enabled ?? false;

/// `'granted'`, `'denied'`, or null if the visitor hasn't chosen.
String? get storedAnalyticsConsent => _dgAnalytics?.consent()?.toDart;

/// Saves the choice and loads Tag Manager (or removes its cookies).
void setAnalyticsConsent({required bool granted}) =>
    _dgAnalytics?.setConsent(granted);
