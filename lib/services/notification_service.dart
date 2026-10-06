import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:signer/src/ui/controllers/appController.dart';
import 'package:flutter_local_notifications/src/platform_flutter_local_notifications.dart';

class NotificationService extends GetxService {
  static NotificationService get to => Get.find();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  
  @override
  void onInit() {
    super.onInit();
    _initializeNotifications();
  }
  
  Future<void> _initializeNotifications() async {
    try {
      // Android settings with high priority
      const AndroidInitializationSettings androidSettings = 
          AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS settings with all permissions
      const DarwinInitializationSettings iosSettings = 
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        requestCriticalPermission: true,
        requestProvisionalPermission: true,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
      );
      
      // Initialize settings
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      // Initialize the plugin
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      // Create notification channel for Android
      await _createNotificationChannel();
      
      // Request permissions explicitly
      await _requestPermissions();
      
      _isInitialized = true;
      print('NotificationService: Initialized successfully');
    } catch (e) {
      print('NotificationService: Error initializing notifications: ${e.runtimeType}');
    }
  }
  
  Future<void> _createNotificationChannel() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        // Create high priority notification channel for transactions
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel(
            'transaction_channel',
            'Transaction Notifications',
            description: 'Notifications for new transactions to sign',
            importance: Importance.max,
            enableVibration: true,
            enableLights: true,
            showBadge: true,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('notification'),
          ),
        );
        
        // Create background processing notification channel
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel(
            'background_processing_channel',
            'Background Processing',
            description: 'Notifications for background auto-signing status',
            importance: Importance.max,
            enableVibration: true,
            enableLights: true,
            showBadge: true,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('notification'),
          ),
        );
        
        print('NotificationService: Android notification channels created');
      }
    } catch (e) {
      print('NotificationService: Error creating notification channels: ${e.runtimeType}');
    }
  }
  
  Future<void> _requestPermissions() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      // Request Android permissions
      if (androidImplementation != null) {
        final bool? granted = await androidImplementation.requestNotificationsPermission();
        print('NotificationService: Android permissions granted: $granted');
        
        if (granted == false) {
          print('NotificationService: WARNING - Android notification permissions not granted');
        }
      }
      
      // For iOS, check and request permissions explicitly with more options
      final IOSFlutterLocalNotificationsPlugin? iosImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      
      if (iosImplementation != null) {
        print('NotificationService: Requesting iOS permissions...');
        
        final bool? iosPermissionsGranted = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          critical: true,
          provisional: true,
        );
        
        print('NotificationService: iOS permissions granted: $iosPermissionsGranted');
        
        if (iosPermissionsGranted == false) {
          print('NotificationService: WARNING - iOS notification permissions not granted');
          print('NotificationService: Please check iOS Settings > Notifications > Your App');
        }
      }
    } catch (e) {
      print('NotificationService: Error requesting permissions: ${e.runtimeType}');
    }
  }
  
  // Method to check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    try {
      // Check Android permissions
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        final bool? enabled = await androidImplementation.areNotificationsEnabled();
        print('NotificationService: Android notifications enabled: $enabled');
        return enabled ?? false;
      }
      
      // Check iOS permissions
      final IOSFlutterLocalNotificationsPlugin? iosImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      
      if (iosImplementation != null) {
        // For iOS, we'll assume permissions are granted if the service is initialized
        // iOS doesn't provide a direct way to check notification permissions
        print('NotificationService: iOS notifications assumed enabled (service initialized)');
        return _isInitialized;
      }
      
      return false;
    } catch (e) {
      print('NotificationService: Error checking notification status: ${e.runtimeType}');
      return false;
    }
  }
  
  /// Check iOS notification settings specifically
  Future<void> checkIOSNotificationSettings() async {
    try {
      final IOSFlutterLocalNotificationsPlugin? iosImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      
      if (iosImplementation != null) {
        print('NotificationService: Checking iOS notification settings...');
        
        // Try to get notification settings
        final NotificationsEnabledOptions? permissionOptions = await iosImplementation.checkPermissions();
        print('NotificationService: iOS notification permission check result: $permissionOptions');
        
        if (permissionOptions != null) {
          print('NotificationService: iOS notification details:');
          print('  - Alert: ${permissionOptions.isAlertEnabled}');
          print('  - Badge: ${permissionOptions.isBadgeEnabled}');
          print('  - Sound: ${permissionOptions.isSoundEnabled}');
          
          if (permissionOptions.isAlertEnabled == false) {
            print('NotificationService: iOS notifications not enabled');
            print('NotificationService: Please enable notifications in iOS Settings > Notifications > Your App');
          }
        } else {
          print('NotificationService: Could not check iOS notification permissions');
        }
      }
    } catch (e) {
      print('NotificationService: Error checking iOS notification settings: ${e.runtimeType}');
    }
  }
  
  // Method to request permissions again if needed
  Future<void> requestPermissionsAgain() async {
    try {
      print('NotificationService: Requesting permissions again...');
      await _requestPermissions();
    } catch (e) {
      print('NotificationService: Error requesting permissions again: ${e.runtimeType}');
    }
  }
  
  void _onNotificationTapped(NotificationResponse response) {
    print('NotificationService: Notification tapped: ${response.payload}');
    
    // Navigate to SignTransactionScreen when notification is tapped
    if (response.payload == 'transaction_ready') {
      try {
        Get.find<AppController>().selectedBottomTabIndex.value = 1;
      } catch (e) {
        print('NotificationService: Error navigating to sign screen: ${e.runtimeType}');
      }
    }
  }
  
  Future<void> showTransactionReadyNotification() async {
    if (!_isInitialized) {
      print('NotificationService: Not initialized, skipping notification');
      return;
    }
    
    try {
      // Check if notifications are enabled
      final bool? areNotificationsEnabled = await _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
      
      print('NotificationService: Notifications enabled: $areNotificationsEnabled');
      
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'transaction_channel',
        'Transaction Notifications',
        channelDescription: 'Notifications for new transactions to sign',
        importance: Importance.max,
        priority: Priority.max,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: Color.fromARGB(255, 255, 0, 0),
        ledOnMs: 1000,
        ledOffMs: 500,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
        timeoutAfter: 30000, // 30 seconds
        autoCancel: false, // Don't auto-cancel so user can see it
        ongoing: false, // Not ongoing, but important
        silent: false, // Make sure it makes sound
        styleInformation: BigTextStyleInformation(
          'New transaction available for signing. Tap to open the app and sign the transaction.',
          htmlFormatBigText: true,
          contentTitle: 'Transaction Ready',
          htmlFormatContentTitle: true,
        ),
      );
      
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
        interruptionLevel: InterruptionLevel.active,
        threadIdentifier: 'transaction_notifications',
        sound: 'default',
        badgeNumber: 1,
        categoryIdentifier: 'TRANSACTION_READY',
        attachments: [],
      );
      
      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // Use a unique ID based on timestamp to avoid conflicts
      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      await _notifications.show(
        notificationId,
        'Transaction Ready',
        'New transaction available for signing',
        details,
        payload: 'transaction_ready',
      );
      
      print('NotificationService: Transaction ready notification shown with ID: $notificationId');
    } catch (e) {
      print('NotificationService: Error showing notification: ${e.runtimeType}');
    }
  }
  
  Future<void> showTransactionSignedNotification(String message) async {
    if (!_isInitialized) {
      print('NotificationService: Not initialized, skipping notification');
      return;
    }
    
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'transaction_channel',
        'Transaction Notifications',
        channelDescription: 'Notifications for new transactions to sign',
        importance: Importance.max,
        priority: Priority.max,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: Color.fromARGB(255, 0, 255, 0),
        ledOnMs: 1000,
        ledOffMs: 500,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        fullScreenIntent: true,
        timeoutAfter: 30000, // 30 seconds
      );
      
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
        interruptionLevel: InterruptionLevel.active,
        threadIdentifier: 'transaction_notifications',
      );
      
      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      await _notifications.show(
        2, // Unique ID
        'Transaction Signed',
        message,
        details,
        payload: 'transaction_signed',
      );
      
      print('NotificationService: Transaction signed notification shown');
    } catch (e) {
      print('NotificationService: Error showing notification: ${e.runtimeType}');
    }
  }
  
  Future<void> showBackgroundProcessingNotification() async {
    if (!_isInitialized) {
      print('NotificationService: Not initialized, skipping background processing notification');
      return;
    }
    
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'background_processing_channel',
        'Background Processing',
        channelDescription: 'Notifications for background auto-signing status',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: true,
        enableVibration: false,
        playSound: false,
        enableLights: false,
        category: AndroidNotificationCategory.service,
        visibility: NotificationVisibility.public,
        ongoing: true, // Make it ongoing so it stays visible
        autoCancel: false, // Don't auto-cancel
        silent: true, // Silent notification
        styleInformation: BigTextStyleInformation(
          'Auto-signing is running in the background. The app will automatically sign new transactions.',
          htmlFormatBigText: true,
          contentTitle: 'Auto-Signing Active',
          htmlFormatContentTitle: true,
        ),
      );
      
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
        presentBanner: false,
        presentList: false,
        interruptionLevel: InterruptionLevel.passive,
        threadIdentifier: 'background_processing',
      );
      
      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // await _notifications.show(
      //   999, // Use a fixed ID for background processing notification
      //   'Auto-Signing Active',
      //   'Background processing is running',
      //   details,
      //   payload: 'background_processing',
      // );
      
      print('NotificationService: Background processing notification shown');
    } catch (e) {
      print('NotificationService: Error showing background processing notification: ${e.runtimeType}');
    }
  }
  
  Future<void> showBackgroundProcessingTestNotification() async {
    if (!_isInitialized) {
      print('NotificationService: Not initialized, skipping background processing test notification');
      return;
    }
    
    try {
      // Get current timestamp for unique notification
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'background_processing_channel',
        'Background Processing',
        channelDescription: 'Notifications for background auto-signing status',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: const Color.fromARGB(255, 0, 255, 255), // Cyan color
        ledOnMs: 1000,
        ledOffMs: 500,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        autoCancel: true, // Auto-cancel after user sees it
        silent: false, // Make it visible and audible
        styleInformation: BigTextStyleInformation(
          'Background API call made at ${DateTime.now().toString().substring(11, 19)}. Auto-signing is working in background!',
          htmlFormatBigText: true,
          contentTitle: 'Background Processing Active',
          htmlFormatContentTitle: true,
        ),
      );
      
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
        interruptionLevel: InterruptionLevel.active,
        threadIdentifier: 'background_processing_test',
        sound: 'default',
        badgeNumber: 1,
        categoryIdentifier: 'BACKGROUND_PROCESSING_TEST',
      );
      
       NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // Use timestamp as unique ID to avoid conflicts
      final int notificationId = timestamp ~/ 1000;
      
      // await _notifications.show(
      //   notificationId,
      //   'Background Processing Active',
      //   'API call made in background',
      //   details,
      //   payload: 'background_processing_test',
      // );
      
      print('NotificationService: Background processing test notification shown with ID: $notificationId');
    } catch (e) {
      print('NotificationService: Error showing background processing test notification: ${e.runtimeType}');
    }
  }
  
  Future<void> showPersistentTimerTestNotification() async {
    if (!_isInitialized) {
      print('NotificationService: Not initialized, skipping persistent timer test notification');
      return;
    }
    
    try {
      // Get current timestamp for unique notification
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'background_processing_channel',
        'Background Processing',
        channelDescription: 'Notifications for background auto-signing status',
        importance: Importance.max,
        priority: Priority.max,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: const Color.fromARGB(255, 255, 165, 0), // Orange color
        ledOnMs: 2000,
        ledOffMs: 1000,
        category: AndroidNotificationCategory.service,
        visibility: NotificationVisibility.public,
        autoCancel: true, // Auto-cancel after user sees it
        silent: false, // Make it visible and audible
        styleInformation: BigTextStyleInformation(
          'Persistent timer triggered at ${DateTime.now().toString().substring(11, 19)}. Background processing is active!',
          htmlFormatBigText: true,
          contentTitle: 'Persistent Timer Active',
          htmlFormatContentTitle: true,
        ),
      );
      
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
        interruptionLevel: InterruptionLevel.active,
        threadIdentifier: 'persistent_timer_test',
        sound: 'default',
        badgeNumber: 1,
        categoryIdentifier: 'PERSISTENT_TIMER_TEST',
      );
      
      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // Use timestamp as unique ID to avoid conflicts
      final int notificationId = timestamp ~/ 1000;
      
      await _notifications.show(
        notificationId,
        'Persistent Timer Active',
        'Background timer triggered',
        details,
        payload: 'persistent_timer_test',
      );
      
      print('NotificationService: Persistent timer test notification shown with ID: $notificationId');
    } catch (e) {
      print('NotificationService: Error showing persistent timer test notification: ${e.runtimeType}');
    }
  }
  
  
  
  /// Show notification when transactions are available to sign
  Future<void> showTransactionAvailableNotification(int transactionCount) async {
    if (!_isInitialized) {
      print('NotificationService: Not initialized, cannot show transaction available notification');
      return;
    }
    
    try {
      print('NotificationService: Showing transaction available notification for $transactionCount transactions');
      
      final String title = transactionCount == 1 
          ? 'Transaction Ready to Sign'
          : '$transactionCount Transactions Ready to Sign';
      
      final String body = transactionCount == 1
          ? 'You have a new transaction that requires your signature'
          : 'You have $transactionCount new transactions that require your signature';
      
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'transaction_available_channel',
        'Transaction Notifications',
        channelDescription: 'Notifications for transactions requiring signature',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: Color.fromARGB(255, 0, 150, 255), // Blue color
        ledOnMs: 1000,
        ledOffMs: 500,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        autoCancel: true,
        silent: false,
      );
      
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
        interruptionLevel: InterruptionLevel.active,
        threadIdentifier: 'transaction_available',
        sound: 'default',
        badgeNumber: 1,
        categoryIdentifier: 'TRANSACTION_AVAILABLE',
      );
      
      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _notifications.show(
        notificationId,
        title,
        body,
        details,
        payload: 'transaction_available',
      );
      
      print('NotificationService: Transaction available notification shown with ID: $notificationId');
    } catch (e) {
      print('NotificationService: Error showing transaction available notification: ${e.runtimeType}');
    }
  }
  
  /// Show notification when signing is successful
  Future<void> showSigningSuccessNotification(int transactionCount) async {
    if (!_isInitialized) {
      print('NotificationService: Not initialized, cannot show signing success notification');
      return;
    }
    
    try {
      print('NotificationService: Showing signing success notification for $transactionCount transactions');
      
      final String title = transactionCount == 1 
          ? 'Transaction Signed Successfully'
          : '$transactionCount Transactions Signed Successfully';
      
      final String body = transactionCount == 1
          ? 'Your transaction has been signed and submitted successfully'
          : 'Your $transactionCount transactions have been signed and submitted successfully';
      
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'signing_success_channel',
        'Signing Success',
        channelDescription: 'Notifications for successful transaction signing',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        enableLights: true,
        ledColor: const Color.fromARGB(255, 0, 255, 0), // Green color
        ledOnMs: 1000,
        ledOffMs: 500,
        visibility: NotificationVisibility.public,
        autoCancel: true,
        silent: false,
      );
      
      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
        interruptionLevel: InterruptionLevel.active,
        threadIdentifier: 'signing_success',
        sound: 'default',
        badgeNumber: 1,
        categoryIdentifier: 'SIGNING_SUCCESS',
      );
      
      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      final int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _notifications.show(
        notificationId,
        title,
        body,
        details,
        payload: 'signing_success',
      );
      
      print('NotificationService: Signing success notification shown with ID: $notificationId');
    } catch (e) {
      print('NotificationService: Error showing signing success notification: ${e.runtimeType}');
    }
  }
  
  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) return;
    
    try {
      await _notifications.cancelAll();
      print('NotificationService: All notifications cancelled');
    } catch (e) {
      print('NotificationService: Error cancelling notifications: ${e.runtimeType}');
    }
  }
}
