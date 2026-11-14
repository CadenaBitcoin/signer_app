import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:signer/src/ui/controllers/appController.dart';
import 'package:signer/src/ui/screens/signInScreen.dart';
import 'package:signer/src/ui/screens/verify_password_screen.dart';

import '../../../services/storage_service.dart';
import '../theme/app_Text_Styles.dart';
import '../theme/colors.dart';
import '../widgets/security_video_launch_gate.dart';
import 'onBoarding.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final appController = Get.find<AppController>();
  final storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkNavigation();
    // Initialize button states based on JWT token
    appController.checkJwtTokenAndUpdateButtons();
  }

  Future<void> _checkNavigation() async {
    await Future.delayed(const Duration(seconds: 2));

    try {
      final isFirstTime = await storage.read(key: 'onboarding_seen');
      final loggedInEmail = await storage.read(key: 'logged_in_user_email');
      final isLoggedIn = await StorageService.getLoginStatus();
      final userData = loggedInEmail != null
          ? await StorageService.getUserByEmail(loggedInEmail)
          : null;

      if (isFirstTime == null) {
        await storage.write(key: 'onboarding_seen', value: 'true');
        Get.off(() => const SecurityVideoLaunchGate(child: OnboardingScreen()));
        return;
      }

      if (userData != null &&
          (userData['email']?.isNotEmpty == true ||
              userData['password']?.isNotEmpty == true)) {
        Get.off(() => const SecurityVideoLaunchGate(child: VerifyPasswordScreen()));
      } else if (userData == null) {
        Get.off(() => const SecurityVideoLaunchGate(child: SignInScreen()));
      } else {
        Get.off(() => const SecurityVideoLaunchGate(child: VerifyPasswordScreen()));
      }
    } catch (e) {
      print('Error in splash screen navigation: $e');
      // Fallback to onboarding if there's any error
      Get.off(() => const SecurityVideoLaunchGate(child: OnboardingScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Replace this with your crypto app logo if available
                Image.asset('assets/transparentLogo.png'),
                const SizedBox(height: 24),
                Text(
                  "CADENA BITCOIN", // Example crypto name
                  style: AppTextStyles.heading1.copyWith(
                    fontSize: 30,
                    color: primaryTextColor.value,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Your gateway to decentralized finance",
                  style: AppTextStyles.body.copyWith(
                    fontSize: 14,
                    color: subTextColor.value,
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
