import 'package:flutter/material.dart';
import 'package:signer/services/push/push_registration_runtime.dart';
import 'package:get/get.dart';
import 'package:signer/services/app_minimize_service.dart';
import 'package:signer/services/auto_signing_service.dart';
import 'package:signer/services/notification_service.dart';
import 'package:signer/services/secure_storage_service.dart';
import 'package:signer/src/ui/controllers/appController.dart';
import 'package:signer/src/ui/screens/splashScreen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required for plugin channels
  
  // Initialize secure storage service first to handle data persistence
  final secureStorageService = SecureStorageService();
  await secureStorageService.initialize();
  
  // Initialize services in correct order
  Get.put(AppController());
  Get.put(NotificationService());
  Get.put(AutoSigningService());
  Get.put(AppMinimizeService());
  Get.put(secureStorageService); // Make secure storage service globally available
  PushRegistrationRuntime.initialize(AppController.API_BASE_URL);

  // OR Option 2: From wallet file
  // final path = await getWalletPath();
  // await DlcWallet.initFromFile(path);
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      PushRegistrationRuntime.authenticated();
    }
    
    // Handle app lifecycle changes globally
    try {
      final autoSigningService = Get.find<AutoSigningService>();
      autoSigningService.handleAppLifecycleChange(state);
    } catch (e) {
      // Service might not be initialized yet
      print('AutoSigningService not available: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const SplashScreen(),
    );
  }
}
