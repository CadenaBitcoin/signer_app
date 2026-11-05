import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:signer/src/ui/theme/app_Text_Styles.dart';
import 'package:signer/src/ui/theme/colors.dart';

import '../../../services/storage_service.dart';
import '../controllers/appController.dart';
import '../widgets/appTextField.dart';
import '../widgets/bottomNavbar.dart';
import '../widgets/primaryButton.dart';
import '../widgets/security_help_link.dart';

class VerifyPasswordScreen extends StatefulWidget {
  const VerifyPasswordScreen({super.key});

  @override
  State<VerifyPasswordScreen> createState() => _VerifyPasswordScreenState();
}

class _VerifyPasswordScreenState extends State<VerifyPasswordScreen> {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  final TextEditingController passwordController = TextEditingController();
  AppController appController = Get.find<AppController>();
  String? email;
  String? passwordError;

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    final storedEmail = await storage.read(key: 'logged_in_user_email');
    setState(() {
      email = storedEmail;
    });
  }

  Future<void> _verifyPassword() async {
    final enteredPassword = passwordController.text.trim();

    if (enteredPassword.isEmpty) {
      setState(() {
        passwordError = "Password is required";
      });
      return;
    }
    appController.loginLoader.value = true;

    final storedEmail = await storage.read(key: 'logged_in_user_email');
    final userData = await StorageService.getUserByEmail(storedEmail!);
    await Future.delayed(const Duration(seconds: 1));

    if (userData != null && enteredPassword == userData['password']) {
      await StorageService.setLoginStatus(true);
      // Success Snackbar
      Get.snackbar('Login Successful', 'Welcome back!',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.withOpacity(0.9),
          colorText: Colors.white,
          duration: Duration(seconds: 1));

      appController.loginLoader.value = false;
      Get.offAll(() => BottomNavBar());
    } else {
      // Incorrect password
      setState(() {
        passwordError = null;
      });
      appController.loginLoader.value = false;
      // Get.snackbar("Error", "Incorrect password",
      //     snackPosition: SnackPosition.BOTTOM,
      //     backgroundColor: Colors.red,
      //     colorText: Colors.white,
      //     duration: Duration(seconds: 4));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        appBar: AppBar(
          backgroundColor: primaryBackgroundColor.value,
          centerTitle: true,
          elevation: 0,
          title: Text(
            "Verify Password",
            style:
                AppTextStyles.heading2.copyWith(color: primaryTextColor.value),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                spacing: 16,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/transparentLogo.png',
                          height: 150,
                        ),
                        Text(
                          "Welcome Back 👋",
                          style: AppTextStyles.heading2.copyWith(
                            color: primaryTextColor.value,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Please verify your password to continue",
                          style: AppTextStyles.body.copyWith(
                            color: subTextColor.value,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: 16,
                    children: [
                      if (email != null) ...[
                        Text(
                          "Email",
                          style: AppTextStyles.body
                              .copyWith(color: subTextColor.value),
                        ),
                        Text(
                          email!,
                          style: AppTextStyles.heading3
                              .copyWith(color: primaryTextColor.value),
                        ),
                        AppTextField(
                          hintText: "Password",
                          controller: passwordController,
                          obscureText: true,
                          isPassword: true,
                        ),
                        if (passwordError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              passwordError!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12),
                            ),
                          ),
                      ],
                    ],
                  ),
                  SizedBox(height: 8),
                  PrimaryButton(
                    text: "Login",
                    onTap: _verifyPassword,
                    isLoading: appController.loginLoader.value,
                    loadingText: "Processing...",
                  ),
                  const SecurityHelpLink(),
                  SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
