/// Whether Tag Manager is configured (never outside the web).
bool get analyticsAvailable => false;

/// `'granted'`, `'denied'`, or null if the visitor hasn't chosen.
String? get storedAnalyticsConsent => null;

void setAnalyticsConsent({required bool granted}) {}
