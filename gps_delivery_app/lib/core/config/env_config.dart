class EnvConfig {
  const EnvConfig._();

  static const String _envSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );

  static const String _envSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static String _runtimeSupabaseUrl = '';
  static String _runtimeSupabaseAnonKey = '';
  static bool _supabaseDisabled = false;

  static String get supabaseUrl => _supabaseDisabled
      ? ''
      : _runtimeSupabaseUrl.isNotEmpty
      ? _runtimeSupabaseUrl
      : _envSupabaseUrl;

  static String get supabaseAnonKey => _supabaseDisabled
      ? ''
      : _runtimeSupabaseAnonKey.isNotEmpty
      ? _runtimeSupabaseAnonKey
      : _envSupabaseAnonKey;

  static void configureSupabaseRuntime({
    required String url,
    required String anonKey,
  }) {
    _supabaseDisabled = false;
    _runtimeSupabaseUrl = url.trim();
    _runtimeSupabaseAnonKey = anonKey.trim();
  }

  static void disableSupabaseRuntime() {
    _supabaseDisabled = true;
    _runtimeSupabaseUrl = '';
    _runtimeSupabaseAnonKey = '';
  }

  static const String nominatimSearchEndpoint =
      'https://nominatim.openstreetmap.org/search';
  static const String osrmRouteEndpoint =
      'https://router.project-osrm.org/route/v1/driving';
  static const String _envDeliveryApiBaseUrl = String.fromEnvironment(
    'DELIVERY_API_BASE_URL',
  );
  static bool get hasBuildDeliveryApiBaseUrl =>
      _envDeliveryApiBaseUrl.isNotEmpty;
  static String _runtimeDeliveryApiBaseUrl = '';
  static String get deliveryApiBaseUrl {
    final raw = _runtimeDeliveryApiBaseUrl.isNotEmpty
        ? _runtimeDeliveryApiBaseUrl
        : _envDeliveryApiBaseUrl;
    if (raw.startsWith('/') &&
        (Uri.base.scheme == 'http' || Uri.base.scheme == 'https') &&
        Uri.base.host.isNotEmpty) {
      return Uri.base.resolve(raw).toString();
    }
    return raw;
  }

  static void configureDeliveryApiRuntime({required String baseUrl}) {
    _runtimeDeliveryApiBaseUrl = baseUrl.trim();
  }

  // Cấu hình Google Maps Platform API (Geocoding, Directions, Places & Tile Server)
  static const String googleMapsGeocodeEndpoint =
      'https://maps.googleapis.com/maps/api/geocode/json';
  static const String googleMapsDirectionsEndpoint =
      'https://maps.googleapis.com/maps/api/directions/json';
  static const String googleMapsPlacesAutocompleteEndpoint =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';

  static const String _envGoogleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );
  static String _runtimeGoogleMapsApiKey = '';

  static String get googleMapsApiKey => _runtimeGoogleMapsApiKey.isNotEmpty
      ? _runtimeGoogleMapsApiKey
      : _envGoogleMapsApiKey;

  static bool get isGoogleMapsKeyConfigured => googleMapsApiKey.isNotEmpty;

  static void configureGoogleMapsRuntime({required String apiKey}) {
    _runtimeGoogleMapsApiKey = apiKey.trim();
  }

  /// Tạo URL tải mảnh bản đồ Google Maps thực tế (Web Mercator Slippy Tile x, y, z)
  /// layer: 'm' (Bản đồ tiêu chuẩn), 'm,traffic' (Giao thông trực tiếp), 'y' (Vệ tinh Hybrid)
  /// hideLabels: ẩn toàn bộ tên đường, địa chỉ, POI và trạm giao thông khi làm nền 3D
  static String buildGoogleMapTileUrl({
    required int x,
    required int y,
    required int z,
    String layer = 'm',
    bool hideLabels = false,
    int scale = 2,
  }) {
    final serverIdx = (x + y).abs() % 4;
    final styleParam = hideLabels
        ? '&apistyle=s.e%3Al%7Cp.v%3Aoff%2Cs.t%3A2%7Cp.v%3Aoff%2Cs.t%3A4%7Cp.v%3Aoff'
        : '';
    final keyParam = isGoogleMapsKeyConfigured
        ? '&key=${Uri.encodeQueryComponent(googleMapsApiKey)}'
        : '';
    return 'https://mt$serverIdx.google.com/vt/lyrs=$layer&hl=vi&x=$x&y=$y&z=$z&scale=$scale$styleParam$keyParam';
  }

  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  static bool get isSupabaseConfigured =>
      supabaseAnonKey.isNotEmpty &&
      !supabaseUrl.contains('your-project.supabase.co');

  // Cấu hình SMTP gửi Email OTP thật & Cổng SMS / Google OAuth 2.0
  static const String _envSmtpHost = String.fromEnvironment(
    'SMTP_HOST',
    defaultValue: 'smtp.gmail.com',
  );
  static const int _envSmtpPort = int.fromEnvironment(
    'SMTP_PORT',
    defaultValue: 465,
  );
  static const String _envSmtpSenderEmail = String.fromEnvironment(
    'SMTP_SENDER_EMAIL',
    defaultValue: '',
  );
  static const String _envSmtpAppPassword = String.fromEnvironment(
    'SMTP_APP_PASSWORD',
    defaultValue: '',
  );
  static const String _envSmsWebhookUrl = String.fromEnvironment(
    'SMS_WEBHOOK_URL',
    defaultValue: '',
  );
  static const String _envOtpEmailWebhookUrl = String.fromEnvironment(
    'OTP_EMAIL_WEBHOOK_URL',
    defaultValue: '',
  );
  static const String _envOtpEmailWebhookToken = String.fromEnvironment(
    'OTP_EMAIL_WEBHOOK_TOKEN',
    defaultValue: '',
  );
  static const String _envSmsProvider = String.fromEnvironment(
    'SMS_PROVIDER',
    defaultValue: 'TEXTBEE',
  );
  static const String _envSmsApiKey = String.fromEnvironment(
    'SMS_API_KEY',
    defaultValue: '',
  );
  static const String _envSmsApiSecret = String.fromEnvironment(
    'SMS_API_SECRET',
    defaultValue: '',
  );
  static const String _envSmsBrandname = String.fromEnvironment(
    'SMS_BRANDNAME',
    defaultValue: '',
  );
  static const String _envGoogleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );
  static const String _envGoogleClientSecret = String.fromEnvironment(
    'GOOGLE_CLIENT_SECRET',
    defaultValue: '',
  );

  static String _runtimeSmtpHost = '';
  static int _runtimeSmtpPort = 0;
  static String _runtimeSmtpSenderEmail = '';
  static String _runtimeSmtpAppPassword = '';
  static String _runtimeSmsWebhookUrl = '';
  static String _runtimeOtpEmailWebhookUrl = '';
  static String _runtimeOtpEmailWebhookToken = '';
  static String _runtimeSmsProvider = '';
  static String _runtimeSmsApiKey = '';
  static String _runtimeSmsApiSecret = '';
  static String _runtimeSmsBrandname = '';
  static String _runtimeGoogleClientId = '';
  static String _runtimeGoogleClientSecret = '';

  static String get smtpHost =>
      _runtimeSmtpHost.isNotEmpty ? _runtimeSmtpHost : _envSmtpHost;
  static int get smtpPort =>
      _runtimeSmtpPort > 0 ? _runtimeSmtpPort : _envSmtpPort;
  static String get smtpSenderEmail => _runtimeSmtpSenderEmail.isNotEmpty
      ? _runtimeSmtpSenderEmail
      : _envSmtpSenderEmail;
  static String get smtpAppPassword =>
      (_runtimeSmtpAppPassword.isNotEmpty
              ? _runtimeSmtpAppPassword
              : _envSmtpAppPassword)
          .replaceAll(' ', '')
          .trim();
  static String get smsWebhookUrl => _runtimeSmsWebhookUrl.isNotEmpty
      ? _runtimeSmsWebhookUrl
      : _envSmsWebhookUrl;
  static String get otpEmailWebhookUrl => _runtimeOtpEmailWebhookUrl.isNotEmpty
      ? _runtimeOtpEmailWebhookUrl
      : _envOtpEmailWebhookUrl;
  static String get otpEmailWebhookToken =>
      _runtimeOtpEmailWebhookToken.isNotEmpty
      ? _runtimeOtpEmailWebhookToken
      : _envOtpEmailWebhookToken;
  static String get smsProvider =>
      _runtimeSmsProvider.isNotEmpty ? _runtimeSmsProvider : _envSmsProvider;
  static String get smsApiKey =>
      _runtimeSmsApiKey.isNotEmpty ? _runtimeSmsApiKey : _envSmsApiKey;
  static String get smsApiSecret =>
      _runtimeSmsApiSecret.isNotEmpty ? _runtimeSmsApiSecret : _envSmsApiSecret;
  static String get smsBrandname =>
      _runtimeSmsBrandname.isNotEmpty ? _runtimeSmsBrandname : _envSmsBrandname;
  static String get googleClientId =>
      _backendGoogleId ??
      (_runtimeGoogleClientId.isNotEmpty
          ? _runtimeGoogleClientId
          : _envGoogleClientId);
  static String get googleClientSecret => _runtimeGoogleClientSecret.isNotEmpty
      ? _runtimeGoogleClientSecret
      : _envGoogleClientSecret;

  static bool get isSmtpConfigured =>
      smtpHost.isNotEmpty &&
      smtpSenderEmail.contains('@') &&
      smtpAppPassword.isNotEmpty;

  static bool get isSmsWebhookConfigured =>
      smsWebhookUrl.startsWith('http://') ||
      smsWebhookUrl.startsWith('https://');

  static bool get isOtpEmailWebhookConfigured =>
      otpEmailWebhookUrl.startsWith('http://') ||
      otpEmailWebhookUrl.startsWith('https://');

  static bool get isEmailOtpConfigured =>
      isOtpEmailWebhookConfigured || isSmtpConfigured;

  static bool get isExternalSmsGatewayConfigured {
    if (_backendSmsReady != null) return _backendSmsReady!;
    final p = smsProvider.toUpperCase();
    if (p == 'TEXTBEE') {
      return smsApiKey.isNotEmpty && smsBrandname.isNotEmpty;
    }
    if (p == 'ESMS') {
      return smsApiKey.isNotEmpty && smsApiSecret.isNotEmpty;
    }
    if (p == 'SPEEDSMS') {
      return smsApiKey.isNotEmpty;
    }
    if (p == 'TWILIO') {
      return smsApiKey.isNotEmpty &&
          smsApiSecret.isNotEmpty &&
          smsBrandname.isNotEmpty;
    }
    return isSmsWebhookConfigured;
  }

  static String formatVietnamPhoneNational(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('84') && digits.length >= 10) {
      return '0${digits.substring(2)}';
    }
    if (!digits.startsWith('0') && digits.length == 9) {
      return '0$digits';
    }
    return digits;
  }

  static String formatVietnamPhoneE164(String raw) {
    final nat = formatVietnamPhoneNational(raw);
    if (nat.isEmpty) return '';
    if (nat.startsWith('0')) {
      return nat.length > 1 ? '+84${nat.substring(1)}' : '';
    }
    return '+84$nat';
  }

  static bool get isGoogleOAuthConfigured =>
      googleClientId.isNotEmpty &&
      googleClientId.contains('.apps.googleusercontent.com');

  static bool? _backendSmsReady;
  static void configureBackendAuth(Map<String, dynamic> value) {
    _backendSmsReady = value['sms'] == true;
    _runtimeGoogleClientId = value['googleClientId']?.toString() ?? '';
    _backendGoogleId = _runtimeGoogleClientId;
  }

  static String? _backendGoogleId;

  static void configureAuthProvidersRuntime({
    String? smtpHost,
    int? smtpPort,
    String? smtpSenderEmail,
    String? smtpAppPassword,
    String? smsWebhookUrl,
    String? otpEmailWebhookUrl,
    String? otpEmailWebhookToken,
    String? smsProvider,
    String? smsApiKey,
    String? smsApiSecret,
    String? smsBrandname,
    String? googleClientId,
    String? googleClientSecret,
  }) {
    if (smtpHost != null) _runtimeSmtpHost = smtpHost.trim();
    if (smtpPort != null && smtpPort > 0) _runtimeSmtpPort = smtpPort;
    if (smtpSenderEmail != null) {
      _runtimeSmtpSenderEmail = smtpSenderEmail.trim();
    }
    if (smtpAppPassword != null) {
      _runtimeSmtpAppPassword = smtpAppPassword.replaceAll(' ', '').trim();
    }
    if (smsWebhookUrl != null) _runtimeSmsWebhookUrl = smsWebhookUrl.trim();
    if (otpEmailWebhookUrl != null) {
      _runtimeOtpEmailWebhookUrl = otpEmailWebhookUrl.trim();
    }
    if (otpEmailWebhookToken != null) {
      _runtimeOtpEmailWebhookToken = otpEmailWebhookToken.trim();
    }
    if (smsProvider != null) {
      _runtimeSmsProvider = smsProvider.trim().toUpperCase();
    }
    if (smsApiKey != null) _runtimeSmsApiKey = smsApiKey.trim();
    if (smsApiSecret != null) _runtimeSmsApiSecret = smsApiSecret.trim();
    if (smsBrandname != null) _runtimeSmsBrandname = smsBrandname.trim();
    if (googleClientId != null) _runtimeGoogleClientId = googleClientId.trim();
    if (googleClientSecret != null) {
      _runtimeGoogleClientSecret = googleClientSecret.trim();
    }
  }

  // Tham số phối cảnh Bản đồ 3D
  static const double map3dDefaultPitch = 55.0;
  static const double map3dMinPitch = 45.0;
  static const double map3dMaxPitch = 60.0;
  static const double map3dNavigationZoom = 17.0;
  static const double map2dOverviewZoom = 14.5;
  static const double buildingExtrusionOpacity = 0.65;
  static const double routeRibbonWidthPx = 8.0;
  static const double routeCasingWidthPx = 2.0;
  static const int mapMaxFps = 30;
  static const int lowBattery2dFallbackPercent = 20;

  // Ngưỡng định vị GPS thời gian thực & Điều phối thông minh
  static const double dispatchRadiusMeters = 3000.0;
  static const int driverAcceptTimeoutSeconds = 28;
  static const double arrivalGeofenceRadiusMeters = 100.0;
  static const double maxValidVehicleSpeedKmh = 120.0;
  static const int stationaryAnomalyAlertSeconds = 900;
  static const int batchTrackingPersistIntervalSeconds = 10;
  static const int maxOfflineRetryBackoffMs = 30000;
}
