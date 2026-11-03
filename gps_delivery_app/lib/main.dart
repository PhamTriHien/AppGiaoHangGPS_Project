import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env_config.dart';
import 'core/config/default_cloud_connection.dart';
import 'core/config/local_auth_config.dart';
import 'core/config/session_slot_storage.dart';
import 'core/integrations/delivery_api_client.dart';
import 'core/integrations/cloud_account_session.dart';
import 'core/integrations/cloud_orders_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'data/datasources/local/app_state_store.dart';
import 'data/datasources/local/sqlite_offline_queue_datasource.dart';
import 'data/datasources/remote/supabase_postgis_datasource.dart';
import 'presentation/bloc/system_architecture_cubit.dart';
import 'presentation/screens/architecture_dashboard_screen.dart';
import 'presentation/screens/admin_portal_screen.dart';
import 'presentation/screens/legacy_admin_portal_screen.dart';
import 'presentation/screens/public_order_tracking_screen.dart';
import 'presentation/screens/cloud_orders_screen.dart';
import 'presentation/screens/marketplace_screen.dart';
import 'presentation/screens/shared_tracking_screen.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final sessionSlot = parseSessionSlotArg(args);
  if (sessionSlot == null) {
    SqliteOfflineQueueDatasource.ensureDesktopFfiInitialized();
  }
  Map<String, dynamic> localConfig = {};
  bool localConfigReadable = true;
  try {
    final config = await loadLocalAuthConfig();
    localConfig = config;
    final savedApiBase = (config['deliveryApiBaseUrl'] as String? ?? '').trim();
    final savedHost = Uri.tryParse(savedApiBase)?.host ?? '';
    final savedIsLoopback =
        savedHost == '127.0.0.1' ||
        savedHost == 'localhost' ||
        savedHost == '::1';
    if (!EnvConfig.hasBuildDeliveryApiBaseUrl || !savedIsLoopback) {
      EnvConfig.configureDeliveryApiRuntime(baseUrl: savedApiBase);
    }
    EnvConfig.configureAuthProvidersRuntime(
      googleClientId: config['googleClientId'] as String?,
      googleClientSecret: config['googleClientSecret'] as String?,
      otpEmailWebhookUrl: config['otpEmailWebhookUrl'] as String?,
      otpEmailWebhookToken: config['otpEmailWebhookToken'] as String?,
    );
  } catch (_) {
    localConfigReadable = false;
    debugPrint('Local authentication configuration could not be loaded.');
  }

  try {
    if (!localConfigReadable) {
      throw const FormatException('Cannot read saved configuration');
    }
    final connection = resolveCloudConnection(saved: localConfig);
    EnvConfig.configureSupabaseRuntime(
      url: connection.url,
      anonKey: connection.publicKey,
    );
  } catch (_) {
    EnvConfig.disableSupabaseRuntime();
    debugPrint(
      'Supabase configuration is invalid; check the public connection settings.',
    );
  }

  if (EnvConfig.isSupabaseConfigured) {
    try {
      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        publishableKey: EnvConfig.supabaseAnonKey,
        authOptions: buildSupabaseAuthOptions(sessionSlot),
      );
      SupabasePostgisDatasource.bindRuntimeClient(
        EnvConfig.supabaseUrl,
        EnvConfig.supabaseAnonKey,
        client: Supabase.instance.client,
      );
    } catch (_) {
      AppStateStore.instance.isOfflineMode = true;
    }
  }

  if (sessionSlot == null) {
    try {
      await AppStateStore.instance.initializeDatabase();
    } catch (_) {}
  }
  if (EnvConfig.deliveryApiBaseUrl.isNotEmpty &&
      EnvConfig.otpEmailWebhookToken.isNotEmpty) {
    try {
      EnvConfig.configureBackendAuth(
        await DeliveryApiClient.instance.request(
          'local-auth/config',
          localAuth: true,
          timeout: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      debugPrint('Backend authentication settings are unavailable.');
    }
  }
  runApp(GpsDeliveryApp(sessionSlot: sessionSlot));
}

class GpsDeliveryApp extends StatefulWidget {
  final String? initialRoute;
  final CloudOrdersService? cloudService;
  final String? sessionSlot;
  const GpsDeliveryApp({
    super.key,
    this.initialRoute,
    this.cloudService,
    this.sessionSlot,
  });

  @override
  State<GpsDeliveryApp> createState() => _GpsDeliveryAppState();
}

class _GpsDeliveryAppState extends State<GpsDeliveryApp> {
  late final _cloudSession = CloudAccountSession(
    service: widget.cloudService ?? CloudOrdersService(),
  );
  late final _themeController = ThemeController(
    session: _cloudSession,
    sessionSlot: widget.sessionSlot,
  );

  String? _resolveBrowserInitialRoute() {
    final path = Uri.base.path;
    final frag = Uri.base.fragment;
    for (final exact in [
      '/admin',
      '/cloud-admin',
      '/legacy-admin',
      '/legacy',
      '/cloud',
    ]) {
      if (path == exact ||
          path == '$exact/' ||
          frag == exact ||
          frag == '$exact/') {
        return exact;
      }
    }
    if (frag.startsWith('/share')) return frag;
    if (frag.startsWith('/track')) return frag;
    if (path == '/track' || path == '/track/') {
      return Uri.base.query.isNotEmpty ? '/track?${Uri.base.query}' : '/track';
    }
    if (path == '/share' || path == '/share/') {
      return Uri.base.query.isNotEmpty ? '/share?${Uri.base.query}' : '/share';
    }
    return null;
  }

  @override
  void dispose() {
    _themeController.dispose();
    _cloudSession.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeControllerScope(
      controller: _themeController,
      child: ListenableBuilder(
        listenable: _themeController,
        builder: (context, _) => BlocProvider(
          create: (_) => SystemArchitectureCubit(),
          child: MaterialApp(
            title: 'GHST - Giao Hàng Siêu Tốc Đa Nền Tảng',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: _themeController.themeMode,
            initialRoute: widget.initialRoute ?? _resolveBrowserInitialRoute(),
        onGenerateInitialRoutes: (name) => [
          MaterialPageRoute<void>(
            settings: RouteSettings(name: name),
            builder: (_) {
              if (name == '/admin') {
                return AdminPortalScreen(session: _cloudSession);
              }
              if (name == '/legacy-admin') {
                return const LegacyAdminPortalScreen();
              }
              if (name == '/share' || name.startsWith('/share?')) {
                return SharedTrackingScreen(
                  token: Uri.parse(name).queryParameters['token'] ?? '',
                  cloudService: _cloudSession.service,
                );
              }
              if (name == '/track' || name.startsWith('/track?')) {
                return PublicOrderTrackingScreen(
                  initialQuery:
                      PublicOrderTrackingScreen.extractQueryFromRouteName(name),
                  cloudService: _cloudSession.service,
                );
              }
              if (name == '/cloud') {
                return MarketplaceScreen(
                  session: _cloudSession,
                  initialShipping: true,
                );
              }
              if (name == '/cloud-admin') {
                return CloudOrdersScreen(session: _cloudSession, admin: true);
              }
              if (name == '/legacy') return const ArchitectureDashboardScreen();
              return MarketplaceScreen(session: _cloudSession);
            },
          ),
        ],
        routes: {
          '/share': (_) =>
              SharedTrackingScreen(cloudService: _cloudSession.service),
          '/': (_) => MarketplaceScreen(session: _cloudSession),
          '/legacy': (_) => const ArchitectureDashboardScreen(),
          '/legacy-admin': (_) => const LegacyAdminPortalScreen(),
          '/admin': (_) => AdminPortalScreen(session: _cloudSession),
          '/cloud': (_) =>
              MarketplaceScreen(session: _cloudSession, initialShipping: true),
          '/cloud-admin': (_) =>
              CloudOrdersScreen(session: _cloudSession, admin: true),
          '/track': (_) =>
              PublicOrderTrackingScreen(cloudService: _cloudSession.service),
        },
        onGenerateRoute: (settings) {
          final routeName = settings.name ?? '';
          if (routeName == '/share' || routeName.startsWith('/share?')) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => SharedTrackingScreen(
                token: Uri.parse(routeName).queryParameters['token'] ?? '',
                cloudService: _cloudSession.service,
              ),
            );
          }
          if (routeName == '/track' || routeName.startsWith('/track?')) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => PublicOrderTrackingScreen(
                initialQuery:
                    PublicOrderTrackingScreen.extractQueryFromRouteName(
                      routeName,
                    ),
                cloudService: _cloudSession.service,
              ),
            );
          }
          return null;
        },
          ),
        ),
      ),
    );
  }
}
