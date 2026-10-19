import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:signer/services/wallet_service.dart';
import 'package:signer/src/ui/controllers/appController.dart';
import 'package:signer/src/ui/screens/login_using_mnemonic_screen.dart';
import 'package:signer/src/ui/screens/signupScreen.dart';
import 'package:signer/src/ui/theme/app_Text_Styles.dart';
import 'package:signer/src/ui/theme/colors.dart';
import 'package:signer/src/ui/widgets/primaryButton.dart';

import '../../../services/storage_service.dart';
import '../widgets/bottomNavbar.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  AppController appController = Get.find<AppController>();

  String? emailError;
  String? passwordError; // Added for password validation
  static final _storage = const FlutterSecureStorage();

  // Selection state for user type
  String? selectedUserType; // 'new' or 'existing'

  bool validateEmail(String email) {
    return GetUtils.isEmail(email);
  }

  void handleProceed() {
    if (selectedUserType == null) {
      Get.snackbar(
        'Selection Required',
        'Please select an option to proceed',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.withOpacity(0.9),
        colorText: Colors.white,
        duration: Duration(seconds: 2),
      );
      return;
    }

    if (selectedUserType == 'new') {
      _showNewUserAlert();
    } else if (selectedUserType == 'existing') {
      _showExistingUserAlert();
    }
  }

  void validateInputs() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    setState(() {
      emailError = validateEmail(email) ? null : "Enter a valid email address";
      // Password validation
      if (password.isEmpty || password == "") {
        passwordError = "Please Enter Password";
      } else {
        passwordError = null;
      }
    });
    if (emailError != null || passwordError != null) return;
    // Set loading state
    setState(() {
      appController.loginLoader.value = true;
    });

    try {
      // Use local storage login instead of API
      final userData = await StorageService.login(email, password);
      await _storage.write(key: 'logged_in_user_email', value: email);

      if (userData != null) {
        // Set isLoggedIn to true on successful login
        await StorageService.setLoginStatus(true);

        Get.offAll(() => BottomNavBar());

        Get.snackbar(
          'Login Successful',
          'Welcome back!',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.withOpacity(0.9),
          colorText: Colors.white,
          duration: Duration(seconds: 1),
        );
      } else {
        Get.snackbar(
          'Login Failed',
          'Incorrect email or password',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.9),
          colorText: Colors.white,
          duration: Duration(seconds: 3),
        );
      }
    } catch (e) {
      debugPrint('Error : ${e.runtimeType}');
      Get.snackbar(
        'Error',
        'An error occurred during login',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withOpacity(0.9),
        colorText: Colors.white,
        duration: Duration(seconds: 3),
      );
    } finally {
      // Reset loading state
      setState(() {
        appController.loginLoader.value = false;
      });
    }

    // API Service calls commented out - now using local storage
    // ApiService().login(email: email, pass: password).then((onValue) {
    //   ApiService().getUserProfile().then((onValue) async {
    //     if (onValue == "OK") {
    //       if (appController.userProfileObject.value.payload?.xpub?.trim() ==
    //           "") {
    //         final mnemonic = await generateMeneMonic();
    //         Get.to(
    //           SeedPhraseScreen(
    //             email: email,
    //             password: password,
    //             mnemonic: mnemonic,
    //           ),
    //         );
    //       } else {
    //         Get.to(ImportWalletScreen(email: "$email", password: ''));
    //       }
    //     }
    //   });
    // });
  }

  @override
  void initState() {
    super.initState();

    emailController.addListener(() {
      if (emailError != null && validateEmail(emailController.text.trim())) {
        setState(() => emailError = null);
      }
    });
    // Listener for password field to clear error when user types
    passwordController.addListener(() {
      if (passwordError != null && passwordController.text.isNotEmpty) {
        setState(() => passwordError = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Sign In to Cadena Bitcoin",
                  style: AppTextStyles.heading2.copyWith(
                    color: primaryTextColor.value,
                  ),
                ),

                const SizedBox(height: 32),

                // Selectable options
                _buildOptionCard(
                  title: "New User",
                  subtitle: "Create a new account",
                  icon: Icons.person_add_outlined,
                  isSelected: selectedUserType == 'new',
                  onTap: () => setState(() => selectedUserType = 'new'),
                ),
                const SizedBox(height: 16),
                _buildOptionCard(
                  title: "Existing User",
                  subtitle: "I already have an account",
                  icon: Icons.login_outlined,
                  isSelected: selectedUserType == 'existing',
                  onTap: () => setState(() => selectedUserType = 'existing'),
                ),
                const SizedBox(height: 32),

                // Proceed button
                PrimaryButton(
                  text: "Proceed",
                  onTap: handleProceed,
                ),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNewUserAlert() {
    Get.dialog(
      AlertDialog(
        backgroundColor: inputFieldBackgroundColor.value,
        title: Text(
          'New User',
          style: AppTextStyles.heading3.copyWith(
            color: primaryTextColor.value,
          ),
        ),
        content: Text(
          'You are registering on Cadena for the first time. You did not introduce a Wallet (SeedPhrase) to Cadena yet.\n\n'
          'Click "Proceed" if you either:\n'
          '• Want Cadena to generate you a new SeedPhrase\n'
          '• Want to import your existing wallet into the Cadena ecosystem\n'
          '• Want to enter a SeedPhrase you generated using external entropy',
          style: AppTextStyles.body.copyWith(
            color: primaryTextColor.value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: subTextColor.value,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              Get.to(SignUpScreen());
            },
            child: Text(
              'Proceed',
              style: AppTextStyles.body.copyWith(
                color: primaryColor.value,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showExistingUserAlert() {
    Get.dialog(
      AlertDialog(
        backgroundColor: inputFieldBackgroundColor.value,
        title: Text(
          'Existing User',
          style: AppTextStyles.heading3.copyWith(
            color: primaryTextColor.value,
          ),
        ),
        content: Text(
          'You are already a Signer level user at Cadena. As we do not store your SeedPhrase, you MUST enter the SeedPhrase you use in the Cadena Ecosystem assigned to your credentials.\n\nClick "Proceed" to Re-Enter your existing 12 word, Cadena used so far.',
          style: AppTextStyles.body.copyWith(
            color: primaryTextColor.value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: subTextColor.value,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              Get.to(LoginUsingMnemonicScreen());
            },
            child: Text(
              'Proceed',
              style: AppTextStyles.body.copyWith(
                color: primaryColor.value,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> generateMeneMonic() async {
    final mnemonic = generateMnemonic();
    return mnemonic;
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.value.withOpacity(0.1) : inputFieldBackgroundColor.value,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryColor.value : borderColor.value,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? primaryColor.value : primaryColor.value.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : primaryColor.value,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.heading3.copyWith(
                      color: isSelected ? primaryColor.value : primaryTextColor.value,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.body.copyWith(
                      color: subTextColor.value,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: primaryColor.value,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
