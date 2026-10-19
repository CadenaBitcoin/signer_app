import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:signer/services/wallet_service.dart';
import 'package:signer/src/ui/theme/app_Text_Styles.dart';
import 'package:signer/src/ui/theme/colors.dart';
import 'package:signer/src/ui/widgets/appTextField.dart';
import 'package:signer/src/ui/widgets/primaryButton.dart';

import 'choose_options_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController confirmEmailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  final RxString emailError = ''.obs;
  final RxString confirmEmailError = ''.obs;
  final RxString passwordError = ''.obs;
  final RxString confirmPasswordError = ''.obs;
  final storage = FlutterSecureStorage();

  String? _validatePassword(String password) {
    const minLength = 3;
    const maxLength = 128;
    final hasLower = RegExp(r'[a-z]').hasMatch(password);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasDigit = RegExp(r'\d').hasMatch(password);
    final hasWhitespace = RegExp(r'\s').hasMatch(password);

    if (password.isEmpty) return "Please enter a password.";
    if (password.length < minLength) return "Password must be at least $minLength characters.";
    if (password.length > maxLength) return "Password must be at most $maxLength characters.";
    if (!hasLower) return "Password must include at least one lowercase letter.";
    if (!hasUpper) return "Password must include at least one uppercase letter.";
    if (!hasDigit) return "Password must include at least one digit.";
    if (hasWhitespace) return "Password cannot contain whitespace.";
    return null; // valid
  }

  // bool isStrongPassword(String password) {
  //   final regex = RegExp(
  //     r'^(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[!@#\$&*~^%()_+=|<>?{}\[\]-]).{8,}$',
  //   );
  //   return regex.hasMatch(password);
  // }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Create An Account",
                  style: AppTextStyles.heading2.copyWith(
                    color: primaryTextColor.value,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 32),

                /// Email
                AppTextField(
                  hintText: "Email",
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                if (emailError.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      emailError.value,
                      style: TextStyle(color: errorColor.value, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                AppTextField(
                  hintText: "Confirm Email",
                  controller: confirmEmailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                if (confirmEmailError.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      confirmEmailError.value,
                      style: TextStyle(color: errorColor.value, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),

                /// Password
                AppTextField(
                  hintText: "Password",
                  controller: passwordController,
                  isPassword: true,
                  obscureText: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\\s')),
                  ],
                ),
                if (passwordError.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      passwordError.value,
                      style: TextStyle(color: errorColor.value, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),

                /// Confirm Password
                AppTextField(
                  hintText: "Confirm Password",
                  controller: confirmPasswordController,
                  isPassword: true,
                  obscureText: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\\s')),
                  ],
                ),
                if (confirmPasswordError.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      confirmPasswordError.value,
                      style: TextStyle(color: errorColor.value, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 32),

                PrimaryButton(
                  text: "Register",
                  onTap: () async {
                    // if (emailError.value.isEmpty &&
                    // passwordError.value.isEmpty &&
                    // confirmPasswordError.value.isEmpty &&
                    // emailController.text.isNotEmpty &&
                    // passwordController.text.isNotEmpty &&
                    // confirmPasswordController.text.isNotEmpty) {
                    // Validate fields before proceeding
                    bool isEmailValid =
                        GetUtils.isEmail(emailController.text.trim());
                    bool isConfirmEmailEntered =
                        confirmEmailController.text.trim().isNotEmpty;
                    bool doEmailsMatch = emailController.text.trim() ==
                        confirmEmailController.text.trim();
                    final password = passwordController.text.trim();
                    final confirmPassword = confirmPasswordController.text.trim();
                    final passwordValidationError = _validatePassword(password);
                    final isConfirmPasswordEntered = confirmPassword.isNotEmpty;
                    bool doPasswordsMatch = passwordController.text ==
                        confirmPasswordController.text;

                    // Update error messages based on current values if button is tapped
                    if (!isEmailValid) {
                      emailError.value = "Enter a valid email";
                    } else {
                      emailError.value = "";
                    }
                    if (!isConfirmEmailEntered) {
                      confirmEmailError.value = "Please confirm your email.";
                    } else if (!doEmailsMatch) {
                      confirmEmailError.value = "Emails do not match";
                    } else {
                      confirmEmailError.value = "";
                    }

                    passwordError.value = passwordValidationError ?? "";

                    if (!isConfirmPasswordEntered) {
                      confirmPasswordError.value =
                          "Please confirm your password.";
                    } else if (!doPasswordsMatch) {
                      confirmPasswordError.value = "Passwords do not match";
                    } else {
                      confirmPasswordError.value = "";
                    }

                    if (isEmailValid &&
                        isConfirmEmailEntered &&
                        passwordValidationError == null &&
                        confirmEmailError.value == "" &&
                        doPasswordsMatch) {
                      // final mnemonic = await generateMeneMonic();
                      // Navigator.push(
                      //   context,
                      //   MaterialPageRoute(
                      //     builder: (_) => SeedPhraseScreen(
                      //       mnemonic: mnemonic,
                      //       email: emailController.text.trim(),
                      //       password: passwordController.text.trim(),
                      //     ),
                      //   ),
                      // );
                      // emailController.clear();
                      // passwordController.clear();
                      // confirmEmailController.clear();
                      // confirmPasswordController.clear();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChooseOptionScreen(
                            email: emailController.text.trim(),
                            password: passwordController.text.trim(),
                            generateMnemonic: generateMeneMonic,
                          ),
                        ),
                      );
                    }
                  },
                ),

                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
/*
                PrimaryButton(
                  text: "Already have an account?",
                  isOutlined: true,
                  onTap: () => Get.to(
                    ChooseOptionScreen(
                      email: emailController.text.trim(),
                      password: passwordController.text.trim(),
                      generateMnemonic: generateMeneMonic,
                    ),
                  ),
                ),*/
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String> generateMeneMonic() async {
    final mnemonic = generateMnemonic();


    return mnemonic;
  }
}
