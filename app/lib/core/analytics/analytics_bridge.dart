// Talks to `window.dgAnalytics` (the Tag Manager loader in web/index.html).
// Outside the web there is no Tag Manager: analytics is never available.
export 'analytics_bridge_stub.dart'
    if (dart.library.js_interop) 'analytics_bridge_web.dart';
