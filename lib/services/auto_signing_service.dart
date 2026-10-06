import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bip39/bip39.dart' as bip39;
import 'package:dlc_wallet/dlc_wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:signer/models/sigReqsByDlcIdsModel.dart';
import 'package:signer/models/userOfferDlcPollModel.dart' as userOfferDlcPollModel;
import 'package:signer/services/dataService/apiService.dart';
import 'package:signer/services/notification_service.dart';
import 'package:signer/services/storage_service.dart';
import 'package:signer/src/ui/controllers/appController.dart';
import 'package:workmanager/workmanager.dart';

class AutoSigningService extends GetxService {
  static AutoSigningService get to => Get.find();
  
  final ApiService _apiService = ApiService();
  final AppController _appController = Get.find<AppController>();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final NotificationService _notificationService = Get.find<NotificationService>();
  
  Timer? _pollingTimer;
  Timer? _foregroundTimer;
  Timer? _backgroundTimer;
  Timer? _persistentTimer;
  bool _isAutoSigningEnabled = false;
  bool _hasProcessedData = false;
  bool _isInitialized = false;
  bool _isAppInForeground = true;
  bool _isBackgroundServiceRunning = false;
  bool _isPersistentTimerRunning = false;
  
  // Observable for UI updates
  var isAutoSigningEnabled = false.obs;
  var isProcessing = false.obs;
  var lastProcessedTime = DateTime.now().obs;
  
  static const String _autoSigningKey = 'auto_signing_enabled';
  static const String _lastProcessedTimeKey = 'last_processed_time';
  
  @override
  void onInit() {
    super.onInit();
    _initializeBackgroundService();
    _loadSettings();
  }
  
  @override
  void onClose() {
    _stopPolling();
    _stopBackgroundService();
    super.onClose();
  }
  
  /// Initialize background service for continuous auto-signing
  Future<void> _initializeBackgroundService() async {
    try {
      print('AutoSigningService: Initializing background service...');
      
      // Initialize WorkManager for background tasks (with error handling)
      try {
        await Workmanager().initialize(
          callbackDispatcher,
          isInDebugMode: false,
        );
        print('AutoSigningService: WorkManager initialized successfully');
      } catch (workManagerError) {
        print('AutoSigningService: WorkManager initialization failed: $workManagerError');
        print('AutoSigningService: Falling back to timer-based background processing');
        // Continue without WorkManager - we'll rely on timers
      }
      
      print('AutoSigningService: Background service initialized');
    } catch (e) {
      print('AutoSigningService: Error initializing background service: ${e.runtimeType}');
    }
  }
  
  Future<void> _loadSettings() async {
    try {
      print('AutoSigningService: Loading settings...');
      final autoSigningValue = await _storage.read(key: _autoSigningKey);
      _isAutoSigningEnabled = autoSigningValue == 'true';
      isAutoSigningEnabled.value = _isAutoSigningEnabled;
      
      print('AutoSigningService: Auto signing enabled: $_isAutoSigningEnabled');
      
      final lastProcessedValue = await _storage.read(key: _lastProcessedTimeKey);
      if (lastProcessedValue != null) {
        lastProcessedTime.value = DateTime.parse(lastProcessedValue);
      }
      
      _isInitialized = true;
      print('AutoSigningService: Service initialized');
      
      // Start polling if auto-signing is enabled
      if (_isAutoSigningEnabled) {
        print('AutoSigningService: Starting polling (auto mode)');
        _startPolling();
      } else {
        print('AutoSigningService: Starting polling (manual mode)');
        _startPolling();
      }
    } catch (e) {
      print('Error loading auto-signing settings: ${e.runtimeType}');
    }
  }
  
  Future<void> _saveSettings() async {
    try {
      await _storage.write(key: _autoSigningKey, value: _isAutoSigningEnabled.toString());
      await _storage.write(key: _lastProcessedTimeKey, value: lastProcessedTime.value.toIso8601String());
    } catch (e) {
      print('Error saving auto-signing settings: ${e.runtimeType}');
    }
  }
  
  Future<void> toggleAutoSigning(bool enabled) async {
    _isAutoSigningEnabled = enabled;
    isAutoSigningEnabled.value = enabled;
    
    await _saveSettings();
    
    // Reset processed flag to allow checking current data in new mode
    _hasProcessedData = false;
    
    if (enabled) {
      _startPolling();
      
      Get.snackbar(
        'Auto Signing',
        'Auto signing enabled - Monitoring for new contracts',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: Duration(seconds: 1),
      );
    } else {
      _startPolling(); // Keep polling for manual mode notifications
      
      Get.snackbar(
        'Manual Mode',
        'Manual signing mode enabled - You will be notified of new transactions',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: Duration(seconds: 3),
      );
    }
  }
  
  void _startPolling() {
    if (!_appController.backendSessionActive.value) {
      print('AutoSigningService: Backend session inactive, not starting polling');
      return;
    }
    print('AutoSigningService: Starting polling...');
    
    // Cancel existing timers
    _pollingTimer?.cancel();
    _backgroundTimer?.cancel();
    
    // Initial poll
    print('AutoSigningService: Performing initial poll');
    _pollForTransactions();
    
    // Set up foreground timer (faster when app is active)
    _pollingTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (_isAppInForeground && !isProcessing.value) {
        print('AutoSigningService: Foreground timer triggered');
        await _pollForTransactions();
      }
    });
    
    // Set up background timer (Android allows background network activity)
    _backgroundTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      // Android allows background network - poll when app is in background
      if (!_isAppInForeground && !isProcessing.value) {
        print('AutoSigningService: Background timer triggered');
        await _pollForTransactions();
      } else if (_isAppInForeground) {
        print('AutoSigningService: Background timer skipped - app in foreground');
      }
    });
    
    // Start background service for reliable background processing
    _startBackgroundService();
    
    // Start persistent timer that works in all states
    _startPersistentTimer();
    
    print('AutoSigningService: Polling timers set up');
  }
  
  void _stopPolling() {
    _pollingTimer?.cancel();
    _backgroundTimer?.cancel();
    _persistentTimer?.cancel();
    _foregroundTimer?.cancel();
    _pollingTimer = null;
    _backgroundTimer = null;
    _persistentTimer = null;
    _foregroundTimer = null;
    _isPersistentTimerRunning = false;
  }

  /// Stop all auth/session-related polling and background work.
  /// Used after Session Invalid → Reset Data so a deleted session cannot keep retrying.
  Future<void> stopAllSessionActivity() async {
    print('AutoSigningService: Stopping all session activity (invalid session teardown)');
    isProcessing.value = false;
    _hasProcessedData = false;
    _stopPolling();
    await _stopBackgroundService();
  }
  
  /// Start background service using WorkManager
  Future<void> _startBackgroundService() async {
    if (_isBackgroundServiceRunning) return;
    
    try {
      print('AutoSigningService: Starting background service...');
      
      // Try to register periodic task for background processing
      try {
        // Use the correct approach based on platform
        if (Platform.isIOS) {
          // For iOS, use BGTaskScheduler approach
          await Workmanager().registerPeriodicTask(
            "auto_signing_task",
            "auto_signing_task",
            frequency: Duration(minutes: 15), // iOS minimum is 15 minutes
            constraints: Constraints(
              networkType: NetworkType.connected,
              requiresBatteryNotLow: false,
              requiresCharging: false,
              requiresDeviceIdle: false,
              requiresStorageNotLow: false,
            ),
          );
        } else {
          // For Android, use standard periodic task
          await Workmanager().registerPeriodicTask(
            "auto_signing_task",
            "auto_signing_task",
            frequency: Duration(minutes: 1), // Android can use shorter intervals
            constraints: Constraints(
              networkType: NetworkType.connected,
              requiresBatteryNotLow: false,
              requiresCharging: false,
              requiresDeviceIdle: false,
              requiresStorageNotLow: false,
            ),
          );
        }
        print('AutoSigningService: WorkManager task registered successfully');
        _isBackgroundServiceRunning = true;
      } catch (workManagerError) {
        print('AutoSigningService: WorkManager task registration failed: $workManagerError');
        print('AutoSigningService: Using timer-based background processing instead');
        // Mark as running even without WorkManager - we have timers
        _isBackgroundServiceRunning = true;
        // Enable enhanced background processing
        _ensureBackgroundProcessing();
      }
      
      // Show background processing notification
      // await _showBackgroundProcessingNotification();
      
      print('AutoSigningService: Background service started');
    } catch (e) {
      print('AutoSigningService: Error starting background service: ${e.runtimeType}');
    }
  }
  
  /// Stop background service
  Future<void> _stopBackgroundService() async {
    if (!_isBackgroundServiceRunning) return;
    
    try {
      print('AutoSigningService: Stopping background service...');
      
      // Try to cancel WorkManager task
      try {
        await Workmanager().cancelByUniqueName("auto_signing_task");
        print('AutoSigningService: WorkManager task cancelled successfully');
      } catch (workManagerError) {
        print('AutoSigningService: WorkManager task cancellation failed: $workManagerError');
        // Continue - timers will be stopped separately
      }
      
      _isBackgroundServiceRunning = false;
      print('AutoSigningService: Background service stopped');
    } catch (e) {
      print('AutoSigningService: Error stopping background service: ${e.runtimeType}');
    }
  }
  
  Future<void> _pollForTransactions() async {
    if (isProcessing.value) return;

    // After Session Invalid reset, do not reuse the deleted/invalid session
    if (!_appController.backendSessionActive.value) {
      print('AutoSigningService: Backend session inactive, skipping transaction polling');
      return;
    }
    
    // Check if user is authenticated by checking if user profile exists
    if (_appController.userProfileObject.value.payload == null) {
      print('AutoSigningService: User not authenticated, skipping transaction polling');
      return;
    }
    
    try {
      print('AutoSigningService: Polling for transactions... (App in foreground: $_isAppInForeground)');
      
      // Add timeout for background API calls to prevent hanging
      final result = await _apiService.userOfferDlcIdsPoll("offer_dlc").timeout(
        Duration(seconds: _isAppInForeground ? 30 : 10), // Shorter timeout in background
        onTimeout: () {
          print('AutoSigningService: API call timed out in background mode');
          return "TIMEOUT";
        },
      );
      
      if (result == "OK") {
        print('AutoSigningService: API call successful');
        
        // Check if we have data
        final payload = _appController.userOfferDlcIdsPollObject.value.payload;
        print('AutoSigningService: Payload length: ${payload?.length ?? 0}');
        
        if (payload != null && payload.isNotEmpty) {
          // Check if this is new data by comparing with last processed time
          final lastProcessed = lastProcessedTime.value;
          final currentDataTimestamp = _appController.userOfferDlcIdsPollObject.value.timestamp;
          
          print('AutoSigningService: Last processed: $lastProcessed');
          print('AutoSigningService: Current timestamp: $currentDataTimestamp');
          
          // Always reset processed flag to allow checking for new transactions
          // The _checkForNewTransactions method will handle filtering and processing
          print('AutoSigningService: Resetting processed flag to allow new transaction checks');
          _hasProcessedData = false;
        }
        
        // Always check for new transactions in both modes
        await _checkForNewTransactions();
      } else {
        print('AutoSigningService: API call failed with result: $result');
        
        // Handle network errors gracefully
        if (result == "FAILED" || result == null || result == "TIMEOUT") {
          print('AutoSigningService: Network error detected, will retry on next poll');
          
          // Check if this is a background network issue
          if (!_isAppInForeground) {
            print('AutoSigningService: Background network error - Android may have restricted network access');
            _checkAndroidBatteryOptimization();
            _handleAndroidBackgroundRestrictions();
            _checkBackgroundRestrictions();
            
            // Show background processing test notification to verify background activity
            // await _notificationService.showBackgroundProcessingTestNotification();
          }
          
          // Don't show error notifications for network issues in background
          // The system will automatically retry on the next poll
        }
      }
    } catch (e) {
      print('Error polling for transactions: ${e.runtimeType}');
      
      // Show error notification in background to help debug
      // if (!_isAppInForeground) {
      //   await _notificationService.showBackgroundProcessingTestNotification();
      // }
    }
  }
  
  Future<void> _checkForNewTransactions() async {
    print('AutoSigningService: Checking for new transactions...');
    print('AutoSigningService: Auto signing enabled: $_isAutoSigningEnabled');
    print('AutoSigningService: Has processed data: $_hasProcessedData');
    print('AutoSigningService: Is processing: ${isProcessing.value}');
    
    // Check if we have data and aren't currently processing
    final payload = _appController.userOfferDlcIdsPollObject.value.payload;
    print('AutoSigningService: Payload available: ${payload != null && payload.isNotEmpty}');
    
    if (payload != null && payload.isNotEmpty && !isProcessing.value) {
      print('AutoSigningService: Processing transaction data');
      
      // Filter DLCs based on user role and status
      final filteredDlcs = await _filterDlcsByUserRole(payload);
      print('AutoSigningService: Filtered DLCs count: ${filteredDlcs.length}');
      
      if (filteredDlcs.isNotEmpty) {
        // Only set processed flag after successful processing
        if (_isAutoSigningEnabled) {
          print('AutoSigningService: Auto mode - signing ${filteredDlcs.length} transactions');
          // Automatic mode - sign all transactions
          await _autoSignTransaction(filteredDlcs);
          _hasProcessedData = true; // Only set after successful auto-signing
        } else {
          print('AutoSigningService: Manual mode - showing notification for ${filteredDlcs.length} transactions');
          // Manual mode - just notify user that there's something to sign
          await _notifyManualSigning(filteredDlcs.length);
          _hasProcessedData = true; // Set after showing notification
        }
        
        // Show notification that there are transactions to sign
        // await _showTransactionAvailableNotification(filteredDlcs.length);
      } else {
        print('AutoSigningService: No DLCs require user signature');
        // Don't set processed flag if no DLCs need processing
      }
    } else {
      print('AutoSigningService: No new transactions to process');
    }
  }
  
  Future<void> _notifyManualSigning([int transactionCount = 1]) async {
    print('AutoSigningService: Showing manual signing notification for $transactionCount transactions');
    print('AutoSigningService: App in foreground: $_isAppInForeground');
    
    final String message = transactionCount == 1 
        ? 'New transaction available for manual signing'
        : '$transactionCount new transactions available for manual signing';
    
    if (_isAppInForeground) {
      // Show snackbar when app is in foreground
      print('AutoSigningService: Showing foreground snackbar');
      Get.snackbar(
        'Transaction${transactionCount > 1 ? 's' : ''} Ready',
        message,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
        snackPosition: SnackPosition.TOP,
        isDismissible: true,
        dismissDirection: DismissDirection.horizontal,
        mainButton: TextButton(
          onPressed: () {
            // Navigate to SignTransactionScreen
            Get.find<AppController>().selectedBottomTabIndex.value = 1;
          },
          child: Text(
            'Sign Now',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else {
      // Show local notification when app is in background
      print('AutoSigningService: App in background, checking notification permissions');
      
      // Check if notifications are enabled
      final bool notificationsEnabled = await _notificationService.areNotificationsEnabled();
      print('AutoSigningService: Notifications enabled: $notificationsEnabled');
      
      // if (notificationsEnabled) {
      //   print('AutoSigningService: Showing background notification');
      //   await _notificationService.showTransactionReadyNotification();
      // } else {
      //   print('AutoSigningService: Notifications not enabled, requesting permissions');
      //   await _notificationService.requestPermissionsAgain();
      //   
      //   // Try to show notification again after requesting permissions
      //   await Future.delayed(Duration(seconds: 1));
      //   await _notificationService.showTransactionReadyNotification();
      // }
    }
  }
  
  /// Show background processing status notification
  Future<void> _showBackgroundProcessingNotification() async {
    try {
      print('AutoSigningService: Showing background processing notification');
      
      // Show a persistent notification indicating background processing is active
      await _notificationService.showBackgroundProcessingNotification();
    } catch (e) {
      print('AutoSigningService: Error showing background processing notification: ${e.runtimeType}');
    }
  }
  
  
  /// Show notification when transactions are available to sign
  Future<void> _showTransactionAvailableNotification(int transactionCount) async {
    try {
      print('AutoSigningService: Showing transaction available notification for $transactionCount transactions');
      await _notificationService.showTransactionAvailableNotification(transactionCount);
    } catch (e) {
      print('AutoSigningService: Error showing transaction available notification: ${e.runtimeType}');
    }
  }
  
  /// Show notification when signing is successful
  Future<void> _showSigningSuccessNotification(int transactionCount) async {
    try {
      print('AutoSigningService: Showing signing success notification for $transactionCount transactions');
      await _notificationService.showSigningSuccessNotification(transactionCount);
    } catch (e) {
      print('AutoSigningService: Error showing signing success notification: ${e.runtimeType}');
    }
  }
  
  /// Handle iOS background restrictions by using app lifecycle events
  void _handleIOSBackgroundRestrictions() {
    // iOS severely restricts background network activity
    // We need to rely on app lifecycle events instead of timers
    print('AutoSigningService: iOS background restrictions detected - using lifecycle events');
  }
  
  /// Check Android battery optimization settings
  void _checkAndroidBatteryOptimization() {
    print('AutoSigningService: Android background network issues detected');
    print('AutoSigningService: Please check the following Android settings:');
    print('AutoSigningService: 1. Settings > Apps > Your App > Battery > Unrestricted');
    print('AutoSigningService: 2. Settings > Battery > Battery Optimization > Your App > Don\'t optimize');
    print('AutoSigningService: 3. Settings > Apps > Your App > Background App Refresh > Allow');
    print('AutoSigningService: 4. Settings > Apps > Your App > Mobile Data & Wi-Fi > Allow background data');
    print('AutoSigningService: 5. Settings > Apps > Your App > Permissions > Allow all permissions');
  }
  
  /// Handle Android background network restrictions by using foreground polling
  void _handleAndroidBackgroundRestrictions() {
    print('AutoSigningService: Android background network restricted - using foreground polling strategy');
    print('AutoSigningService: Will poll aggressively when app comes to foreground');
    
    // Increase foreground polling frequency when background is restricted
    if (_foregroundTimer != null) {
      _foregroundTimer!.cancel();
    }
    
    // More aggressive foreground polling (every 3 seconds instead of 5)
    _foregroundTimer = Timer.periodic(Duration(seconds: 3), (timer) async {
      if (_isAppInForeground && !isProcessing.value) {
        print('AutoSigningService: Aggressive foreground timer triggered');
        await _pollForTransactions();
      }
    });
    
    print('AutoSigningService: Aggressive foreground polling started (3-second intervals)');
  }
  
  /// Check if we're in a restricted background state and adjust strategy
  void _checkBackgroundRestrictions() {
    // If we're getting consistent network failures in background, adjust strategy
    if (!_isAppInForeground) {
      print('AutoSigningService: Background restrictions detected - switching to foreground-only strategy');
      print('AutoSigningService: Background timers will be less aggressive');
      
      // Reduce background timer frequency to avoid battery drain
      if (_backgroundTimer != null) {
        _backgroundTimer!.cancel();
      }
      
      // Less frequent background polling to avoid battery optimization
      _backgroundTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
        if (!_isAppInForeground && !isProcessing.value) {
          print('AutoSigningService: Reduced frequency background timer triggered');
          await _pollForTransactions();
        }
      });
    }
  }

  /// Filter DLCs based on user role and status
  /// Implements the logic from the reference implementation:
  /// - For offer_dlc: always needs signature
  /// - For sign_ini: only if user is acceptor
  /// - For sign_acc: only if user is initiator
  Future<List<userOfferDlcPollModel.Payload>> _filterDlcsByUserRole(List<userOfferDlcPollModel.Payload> dlcs) async {
    final userEmail = await _getUserEmail();
    if (userEmail == null) {
      print('AutoSigningService: Could not determine user email');
      return [];
    }
    
    final filteredDlcs = <userOfferDlcPollModel.Payload>[];
    
    for (final dlc in dlcs) {
      final status = dlc.status;
      bool needsSignature = false;
      
      if (status == 'offer_dlc') {
        // Always needs signature for offer_dlc
        needsSignature = true;
        print('AutoSigningService: DLC ${dlc.dlcId} needs signature (offer_dlc)');
      } else {
        // Check user role and status
        final userRole = _determineUserRole(dlc, userEmail);
        
        if (status == 'sign_acc' && userRole == 'ini') {
          // Initiator needs to sign when acceptor has signed
          needsSignature = true;
          print('AutoSigningService: DLC ${dlc.dlcId} needs signature (initiator for sign_acc)');
        } else if (status == 'sign_ini' && userRole == 'acc') {
          // Acceptor needs to sign when initiator has signed
          needsSignature = true;
          print('AutoSigningService: DLC ${dlc.dlcId} needs signature (acceptor for sign_ini)');
        } else {
          print('AutoSigningService: DLC ${dlc.dlcId} does not need signature (role: $userRole, status: $status)');
        }
      }
      
      if (needsSignature) {
        filteredDlcs.add(dlc);
      }
    }
    
    return filteredDlcs;
  }
  
  /// Determine user's role in a DLC (initiator or acceptor)
  String? _determineUserRole(userOfferDlcPollModel.Payload dlc, String userEmail) {
    if (dlc.iniEmail == userEmail) {
      return 'ini'; // Initiator
    } else if (dlc.accEmail == userEmail) {
      return 'acc'; // Acceptor
    }
    return null; // User is not part of this DLC
  }
  
  /// Get current user's email
  Future<String?> _getUserEmail() async {
    try {
      return await StorageService.getLoggedInEmail();
    } catch (e) {
      print('AutoSigningService: Error getting user email: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> _autoSignTransaction([List<userOfferDlcPollModel.Payload>? filteredDlcs]) async {
    if (isProcessing.value) return;
    
    isProcessing.value = true;
    
    try {
      // Show loading indicator only in foreground
      if (_isAppInForeground) {
        Get.snackbar(
          'Auto Signing',
          'Automatically processing transaction...',
          backgroundColor: Colors.blue,
          colorText: Colors.white,
          duration: Duration(seconds: 3),
        );
      } else {
        print('AutoSigningService: Auto-signing in background mode');
        // Show background processing notification
        // await _notificationService.showBackgroundProcessingTestNotification();
      }

      // Use filtered DLCs if provided, otherwise fall back to all DLCs
      final dlcsToProcess = filteredDlcs ?? _appController.userOfferDlcIdsPollObject.value.payload ?? [];
      if (dlcsToProcess.isEmpty) {
        print('AutoSigningService: No DLCs to process');
        return;
      }

      print('AutoSigningService: Processing ${dlcsToProcess.length} DLCs sequentially (Background: ${!_isAppInForeground})');
      
      // Process all DLCs sequentially
      for (int i = 0; i < dlcsToProcess.length; i++) {
        final dlc = dlcsToProcess[i];
        final dlcId = dlc.dlcId ?? "";
        
        if (dlcId.isNotEmpty) {
          print('AutoSigningService: Processing DLC ${i + 1}/${dlcsToProcess.length}: $dlcId');
          
          // Add timeout for background API calls
          final result = await _apiService.sigReqsByDlcIds([dlcId]).timeout(
            Duration(seconds: _isAppInForeground ? 30 : 15), // Shorter timeout in background
            onTimeout: () {
              print('AutoSigningService: sigReqsByDlcIds timed out for DLC $dlcId');
              return "TIMEOUT";
            },
          );
          
          if (result == "OK") {
            if (_appController.sigReqsByDlcIdsModelObject.value.payload!.isNotEmpty) {
              // Add timeout for signing process
              await _signFundingInput(
                dlcId: dlcId,
                inputReqs: _appController.sigReqsByDlcIdsModelObject.value.payload?[0].funding?.inputReqs
              ).timeout(
                Duration(seconds: _isAppInForeground ? 60 : 30), // Shorter timeout in background
                onTimeout: () {
                  print('AutoSigningService: Signing process timed out for DLC $dlcId');
                  throw TimeoutException('Signing process timed out', Duration(seconds: 30));
                },
              );
              
              // Show success message for each DLC only in foreground
              if (_isAppInForeground) {
                Get.snackbar(
                  'Auto Signed',
                  'DLC ${i + 1}/${dlcsToProcess.length} signed successfully',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                  duration: Duration(seconds: 2),
                );
              } else {
                print('AutoSigningService: DLC ${i + 1}/${dlcsToProcess.length} signed successfully in background');
                // Show background success notification
                // await _notificationService.showBackgroundProcessingTestNotification();
              }
              
              // Small delay between DLCs to avoid overwhelming the system
              if (i < dlcsToProcess.length - 1) {
                await Future.delayed(Duration(seconds: _isAppInForeground ? 1 : 2)); // Longer delay in background
              }
            } else {
              print('AutoSigningService: No signature requests found for DLC $dlcId');
              if (_isAppInForeground) {
                Get.snackbar(
                  'Warning',
                  'No signature requests found for DLC ${i + 1}/${dlcsToProcess.length}',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                  duration: Duration(seconds: 3),
                );
              }
            }
          } else {
            print('AutoSigningService: Failed to fetch signature requests for DLC $dlcId (Result: $result)');
            if (_isAppInForeground) {
              Get.snackbar(
                'Error',
                'Failed to fetch signature requests for DLC ${i + 1}/${dlcsToProcess.length}',
                backgroundColor: Colors.red,
                colorText: Colors.white,
                duration: Duration(seconds: 3),
              );
            } else {
              // Show background error notification
              // await _notificationService.showBackgroundProcessingTestNotification();
            }
          }
        } else {
          print('AutoSigningService: Empty DLC ID for DLC ${i + 1}/${dlcsToProcess.length}');
        }
      }
      
      print('AutoSigningService: Completed processing all ${dlcsToProcess.length} DLCs');
    } catch (e) {
      print('Error in auto signing: ${e.runtimeType}');
      _hasProcessedData = false; // Reset to allow retry
      
      // Show error notification in background
      // if (!_isAppInForeground) {
      //   await _notificationService.showBackgroundProcessingTestNotification();
      // }
    } finally {
      isProcessing.value = false;
    }
  }
  
  Future<void> _signFundingInput({
    List<InputReqs>? inputReqs,
    String? dlcId,
  }) async {
    if (inputReqs == null || inputReqs.isEmpty) {
      Get.snackbar(
        'Error',
        'No signature requests available for this DLC.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
      );
      return;
    }

    if (dlcId == null || dlcId.isEmpty) {
      Get.snackbar(
        'Error',
        'Invalid DLC ID provided.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
      );
      return;
    }

    try {
      // Check if library is loaded first
      if (!DlcWallet.isLibraryLoaded()) {
        Get.snackbar(
          'Error',
          'DLC wallet library is not loaded. Please restart the app.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: Duration(seconds: 5),
        );
        return;
      }

      // Ensure wallet is initialized
      if (!await DlcWallet.isWalletInitialized()) {
        final _storage = const FlutterSecureStorage();
        final emailKey = 'logged_in_user_email';
        final storedEmail = await _storage.read(key: emailKey);

        if (storedEmail == null) {
          Get.snackbar(
            'Error',
            'User session not found. Please log in again.',
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: Duration(seconds: 4),
          );
          return;
        }

        final mnemonic = await _getMnemonic(storedEmail);
        if (mnemonic == null) {
          Get.snackbar(
            'Error',
            'Wallet mnemonic not found. Please restore your wallet.',
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: Duration(seconds: 4),
          );
          return;
        }

        final entropy = bip39.mnemonicToEntropy(mnemonic);
        await DlcWallet.initWithEntropy(entropy, _appController.currentEnvironment);
      }

      // Collect all funding signatures
      List<String> fundingSignatures = [];

      for (final req in inputReqs!) {
        final hash = req.sighash;
        final signerIndex = req.signerIndex;
        final signerPubkey = req.signerPubkey;

        if (hash == null || signerIndex == null || signerPubkey == null) {
          throw Exception('Invalid signature request parameters');
        }

        final signature = await DlcWallet.signHashEcdsa(hash, signerIndex, signerPubkey);
        fundingSignatures.add(signature);
      }

      // Get refund signature
      String refundSignature = '';
      final refundReqs = _appController.sigReqsByDlcIdsModelObject.value.payload![0].refund?.inputReqs;
      if (refundReqs != null && refundReqs.isNotEmpty) {
        final refundReq = refundReqs[0];
        if (refundReq.sighash != null && refundReq.signerIndex != null && refundReq.signerPubkey != null) {
          refundSignature = await DlcWallet.signHashEcdsa(refundReq.sighash!, refundReq.signerIndex!, refundReq.signerPubkey!);
        }
      }

      // Get adaptor signature points
      String adaptorSigPoints = '';
      final cets = _appController.sigReqsByDlcIdsModelObject.value.payload![0].cets;
      if (cets != null && cets.intervalWildcards != null && cets.intervalWildcards!.isNotEmpty) {
        try {
          // Parse the string parameters into lists
          final noncesList = cets.nonces?.split(' ').where((s) => s.isNotEmpty).toList() ?? [];
          final intervalWildcardsList = cets.intervalWildcards?.split(' ').where((s) => s.isNotEmpty).toList() ?? [];
          final sighashesList = cets.sighashes?.split(' ').where((s) => s.isNotEmpty).toList() ?? [];

          if (noncesList.isEmpty) {
            print('No CET parameters provided');
            throw Exception('No CET parameters provided');
          }

          // Validate that we have the required CET parameters
          if (cets.signerIndex == null || cets.signerPubkey == null || cets.oraclePubkey == null) {
            throw Exception('Missing required CET parameters');
          }

          // Use CET-specific parameters
          final signatures = await DlcWallet.createCetAdaptorSigs(
            numDigits: cets.numDigits ?? 2,
            numCets: cets.numCets ?? intervalWildcardsList.length,
            digitStringTemplate: cets.digitStringTemplate ?? 'BTCUSD',
            oraclePublicKey: cets.oraclePubkey!,
            signingKeyIndex: cets.signerIndex!,
            signingPublicKey: cets.signerPubkey!,
            nonces: noncesList,
            intervalWildcards: intervalWildcardsList,
            sighashes: sighashesList,
          );

          adaptorSigPoints = signatures.join(' '); // Space-separated signatures
          print('Generated ${signatures.length} CET adaptor signatures');
        } catch (e) {
          print('Error creating CET adaptor signatures: ${e.runtimeType}');
          // Continue without adaptor signatures
        }
      }

      // Call API with all parameters - add timeout for background mode
      final result = await _apiService.offerDlcSignatures(
        dlc_id: '$dlcId', 
        funding_sigs: fundingSignatures.join(' '), 
        refund_sig: refundSignature, 
        adaptor_sig_points: adaptorSigPoints
      ).timeout(
        Duration(seconds: _isAppInForeground ? 60 : 30), // Shorter timeout in background
        onTimeout: () {
          print('AutoSigningService: offerDlcSignatures API call timed out for DLC $dlcId');
          return "TIMEOUT";
        },
      );

      if (result == 'OK') {
        // Show success message
        final responseMessage = _appController.dlcSignatureResponseObject.value.message ?? 'DLC signatures submitted successfully!';
        
        print('AutoSigningService: DLC $dlcId signed successfully (Background: ${!_isAppInForeground})');
        
        // Show success notification
        // await _showSigningSuccessNotification(1);
        
        if (_isAppInForeground) {
          // Show snackbar when app is in foreground
          Get.snackbar(
            'Auto Signing Complete',
            responseMessage,
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: Duration(seconds: 1),
            snackPosition: SnackPosition.TOP,
            isDismissible: true,
            dismissDirection: DismissDirection.horizontal,
          );
        } else {
          // Show local notification when app is in background
          // await _notificationService.showTransactionSignedNotification(responseMessage);
          // Also show background processing test notification
          // await _notificationService.showBackgroundProcessingTestNotification();
        }

        // Update last processed time
        lastProcessedTime.value = DateTime.now();
        await _saveSettings();

        // Refresh the DLC list to show updated status - with timeout
        await _apiService.userOfferDlcIdsPoll("offer_dlc").timeout(
          Duration(seconds: _isAppInForeground ? 30 : 15),
          onTimeout: () {
            print('AutoSigningService: userOfferDlcIdsPoll timed out after signing');
            return "TIMEOUT";
          },
        );
        
        // Reset the processed flag to allow processing new transactions
        _hasProcessedData = false;
      } else {
        // Show specific error messages based on the result
        String errorMessage = 'Failed to submit DLC signatures. Please try again.';

        switch (result) {
          case 'BAD_REQUEST':
            errorMessage = 'Invalid DLC ID provided. Please check the contract details.';
            break;
          case 'FORBIDDEN':
            errorMessage = 'You are not authorized to sign this DLC contract.';
            break;
          case 'SERVER_ERROR':
            errorMessage = 'Server error occurred. Please try again later.';
            break;
          case 'FAILED':
          default:
            errorMessage = 'Failed to submit DLC signatures. Please try again.';
            break;
        }

        // Only show error notifications when app is in foreground
        if (_isAppInForeground) {
          Get.snackbar(
            'Error',
            errorMessage,
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: Duration(seconds: 4),
          );
        } else {
          print('AutoSigningService: Error in background - will retry on next poll');
        }
        
        // Reset the processed flag to allow retry
        _hasProcessedData = false;
      }
    } catch (e) {
      print('Error in signFundingInput: ${e.runtimeType}');
      Get.snackbar(
        'Error',
        'An error occurred while signing transactions: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
      );
      
      // Reset the processed flag to allow retry
      _hasProcessedData = false;
    }
  }

  Future<String?> _getMnemonic(String email) async {
    final userKey = 'user_$email';
    final storedData = await _storage.read(key: userKey);
    if (storedData == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(storedData);
    return decoded['mnemonic'] as String?;
  }
  
  // Public methods for external control
  bool get isEnabled => _isAutoSigningEnabled;
  
  void resumePolling() {
    if (!_appController.backendSessionActive.value) {
      print('AutoSigningService: Backend session inactive, not resuming polling');
      return;
    }
    if (_isAutoSigningEnabled && _pollingTimer == null) {
      _startPolling();
    }
    
    // Also ensure persistent timer is running
    if (_isAutoSigningEnabled && !_isPersistentTimerRunning) {
      _startPersistentTimer();
    }
  }
  
  void pausePolling() {
    _stopPolling();
  }
  
  Future<void> forceRefresh() async {
    // Check if user is authenticated
    if (!_appController.backendSessionActive.value ||
        _appController.userProfileObject.value.payload == null) {
      Get.snackbar(
        'Authentication Required',
        'Please log in to check for transactions',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
      );
      return;
    }
    
    // Reset the processed flag to allow immediate checking
    _hasProcessedData = false;
    
    // Show feedback to user
    Get.snackbar(
      'Refreshing',
      'Refreshing transaction data...',
      backgroundColor: Colors.blue,
      colorText: Colors.white,
      duration: Duration(seconds: 3),
    );
    
    // Immediately check for new transactions
    await _pollForTransactions();
  }
  
  // Method to manually trigger a check for new transactions
  Future<void> checkForNewTransactions() async {
    // Check if user is authenticated
    if (!_appController.backendSessionActive.value ||
        _appController.userProfileObject.value.payload == null) {
      Get.snackbar(
        'Authentication Required',
        'Please log in to check for transactions',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
      );
      return;
    }
    
    // Reset the processed flag to allow immediate checking
    _hasProcessedData = false;
    
    // Show feedback to user
    Get.snackbar(
      'Checking',
      'Checking for new transactions...',
      backgroundColor: Colors.blue,
      colorText: Colors.white,
      duration: Duration(seconds: 3),
    );
    
    // Immediately check for new transactions
    await _pollForTransactions();
  }
  
  // Method to reset processed flag when new data is detected
  void resetProcessedFlag() {
    print('AutoSigningService: Resetting processed flag');
    _hasProcessedData = false;
  }
  
  // Method to force check for new transactions (bypasses processed flag)
  Future<void> forceCheckForNewTransactions() async {
    print('AutoSigningService: Force checking for new transactions');
    _hasProcessedData = false;
    await _pollForTransactions();
  }
  
  /// Force restart all timers (useful when logs get paused)
  void forceRestartTimers() {
    print('AutoSigningService: Force restarting all timers...');
    
    // Stop existing timers
    _stopPolling();
    
    // Restart all timers
    if (_isAutoSigningEnabled) {
      _startPolling();
    }
    
    print('AutoSigningService: All timers restarted');
  }
  
  /// Debug method to test background processing
  Future<void> testBackgroundProcessing() async {
    print('AutoSigningService: Testing background processing...');
    print('AutoSigningService: App in foreground: $_isAppInForeground');
    print('AutoSigningService: Auto signing enabled: $_isAutoSigningEnabled');
    print('AutoSigningService: Background service running: $_isBackgroundServiceRunning');
    print('AutoSigningService: Persistent timer running: $_isPersistentTimerRunning');
    
    // Show test notification
    // await _notificationService.showBackgroundProcessingTestNotification();
    
    // Force a poll to test API connectivity
    await _pollForTransactions();
  }
  
  /// Enable auto-signing for testing
  Future<void> enableAutoSigningForTesting() async {
    print('AutoSigningService: Enabling auto-signing for testing...');
    await toggleAutoSigning(true);
    print('AutoSigningService: Auto-signing enabled. Testing background processing...');
    await testBackgroundProcessing();
  }
  
  /// Get current auto-signing status
  Map<String, dynamic> getAutoSigningStatus() {
    return {
      'isAutoSigningEnabled': _isAutoSigningEnabled,
      'isAppInForeground': _isAppInForeground,
      'isBackgroundServiceRunning': _isBackgroundServiceRunning,
      'isPersistentTimerRunning': _isPersistentTimerRunning,
      'isProcessing': isProcessing.value,
      'hasProcessedData': _hasProcessedData,
      'lastProcessedTime': lastProcessedTime.value.toIso8601String(),
    };
  }
  
  
  // Background processing methods
  Future<void> handleAppLifecycleChange(AppLifecycleState state) async {
    if (!_appController.backendSessionActive.value) {
      print('AutoSigningService: Backend session inactive — ignoring lifecycle poll/restart');
      if (state == AppLifecycleState.resumed) {
        _isAppInForeground = true;
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        _isAppInForeground = false;
      }
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground
        _isAppInForeground = true;
        print('AutoSigningService: App resumed - now in foreground');
        
        // Android background restrictions - immediately poll when app comes to foreground
        print('AutoSigningService: Android background restriction workaround - immediate poll');
        await _pollForTransactions();
        
        // Also poll again after a short delay to catch any missed transactions
        Future.delayed(Duration(seconds: 2), () async {
          if (_isAppInForeground && _appController.backendSessionActive.value) {
            print('AutoSigningService: Follow-up poll after app resume');
            await _pollForTransactions();
          }
        });
        
        // Resume foreground polling and ensure background service is running
        if (_isAutoSigningEnabled) {
          resumePolling();
          _startBackgroundService(); // Ensure background service is active
          
          // Check if timers are still running, restart if needed
          if (!_isPersistentTimerRunning) {
            print('AutoSigningService: Persistent timer not running, restarting...');
            _startPersistentTimer();
          }
        }
        
        // Show notification if there are pending transactions
        _checkForPendingTransactions();
        break;
        
      case AppLifecycleState.paused:
        // App went to background - ensure background service is running
        _isAppInForeground = false;
        print('AutoSigningService: App paused - ensuring background service is active');
        
        
        // Ensure background service is running for reliable background processing
        if (_isAutoSigningEnabled) {
          _startBackgroundService();
          // Ensure persistent timer is running
          if (!_isPersistentTimerRunning) {
            _startPersistentTimer();
          }
          // Also trigger an immediate check when going to background
          _pollForTransactions();
        }
        break;
        
      case AppLifecycleState.detached:
        // App is being terminated - ensure background service continues
        _isAppInForeground = false;
        print('AutoSigningService: App detached - ensuring background service continues');
        
        // Don't stop background service, let it continue
        break;
        
      case AppLifecycleState.inactive:
        // App is inactive - continue background processing
        _isAppInForeground = false;
        print('AutoSigningService: App inactive - continuing background processing');
        
        break;
        
      case AppLifecycleState.hidden:
        // App is hidden - continue background processing
        _isAppInForeground = false;
        print('AutoSigningService: App hidden - continuing background processing');
        
        break;
    }
  }
  
  /// Check for pending transactions when app resumes
  Future<void> _checkForPendingTransactions() async {
    try {
      print('AutoSigningService: Checking for pending transactions on app resume...');
      
      // Force a check for new transactions
      _hasProcessedData = false;
      await _pollForTransactions();
      
      // If auto-signing is enabled, also try to process any pending transactions
      if (_isAutoSigningEnabled) {
        print('AutoSigningService: Auto-signing enabled, checking for pending transactions to sign...');
        await _checkForNewTransactions();
      }
    } catch (e) {
      print('AutoSigningService: Error checking for pending transactions: ${e.runtimeType}');
    }
  }
  
  // Method to check if background processing is supported
  bool get supportsBackgroundProcessing => true; // For now, assume it's supported
  
  // Method to enable/disable background processing
  Future<void> setBackgroundProcessingEnabled(bool enabled) async {
    // This would typically involve platform-specific code
    // For now, we'll just log the preference
    print('Background processing ${enabled ? 'enabled' : 'disabled'}');
  }
  
  /// Start persistent timer that works in all app states
  void _startPersistentTimer() {
    if (!_appController.backendSessionActive.value) {
      print('AutoSigningService: Backend session inactive, not starting persistent timer');
      return;
    }
    if (_isPersistentTimerRunning) return;
    
    _isPersistentTimerRunning = true;
    print('AutoSigningService: Starting persistent timer for continuous processing...');
    
    // Create a persistent timer that runs regardless of app state
    _persistentTimer = Timer.periodic(Duration(seconds: 12), (timer) async {
      try {
        print('AutoSigningService: Persistent timer triggered (app in foreground: $_isAppInForeground)');
        
        
        // Poll for transactions regardless of app state (Android allows background network)
        if (!isProcessing.value) {
          await _pollForTransactions();
        } else {
          print('AutoSigningService: Persistent timer skipped - already processing');
        }
      } catch (e) {
        print('AutoSigningService: Persistent timer error: ${e.runtimeType}');
      }
    });
    
    print('AutoSigningService: Persistent timer started');
  }
  
  /// Enhanced background processing that works even without WorkManager
  void _ensureBackgroundProcessing() {
    if (!_isAutoSigningEnabled) return;
    
    // If WorkManager failed, rely more heavily on timers
    if (!_isBackgroundServiceRunning) {
      print('AutoSigningService: WorkManager not available, using enhanced timer-based processing');
      
      // Create a more aggressive timer for background processing
      Timer.periodic(Duration(seconds: 8), (timer) async {
        if (!_isAppInForeground && !isProcessing.value) {
          print('AutoSigningService: Enhanced background timer triggered');
          await _pollForTransactions();
        }
      });
    }
  }
}

/// Background task callback dispatcher for WorkManager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('Background task executed: $task');
    
    try {
      // Handle different task types
      switch (task) {
        case "auto_signing_task":
          print('Background task: Processing auto-signing task...');
          await _handleAutoSigningTask();
          break;
        case Workmanager.iOSBackgroundTask:
          print('Background task: iOS Background Fetch task...');
          await _handleAutoSigningTask();
          break;
        default:
          print('Background task: Unknown task type: $task');
          break;
      }
      
      return Future.value(true);
    } catch (e) {
      print('Background task error: ${e.runtimeType}');
      return Future.value(false);
    }
  });
}

/// Handle auto-signing background task
Future<void> _handleAutoSigningTask() async {
  try {
    // Initialize services if needed
    if (!Get.isRegistered<AutoSigningService>()) {
      // Re-initialize services for background task
      Get.put(AutoSigningService());
    }
    
    final autoSigningService = Get.find<AutoSigningService>();
    
    // Check if auto-signing is enabled
    if (autoSigningService.isEnabled) {
      print('Background task: Auto-signing is enabled, checking for transactions...');
      
      // Force check for new transactions
      await autoSigningService.forceCheckForNewTransactions();
      
      print('Background task: Transaction check completed');
    } else {
      print('Background task: Auto-signing is disabled, skipping transaction check');
    }
  } catch (e) {
    print('Background task: Error in auto-signing task: ${e.runtimeType}');
  }
}
