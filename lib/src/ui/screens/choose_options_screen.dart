// lib/src/ui/screens/choose_options_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:signer/src/ui/screens/createWallet/seed_phrase.dart';
import 'package:signer/src/ui/screens/mnemonic_screen.dart';

import '../theme/colors.dart';
import '../widgets/primaryButton.dart';
import '../widgets/security_help_link.dart';

class ChooseOptionScreen extends StatefulWidget {
  final String email;
  final String password;
  final Future<String> Function() generateMnemonic;

  const ChooseOptionScreen({
    super.key,
    required this.email,
    required this.password,
    required this.generateMnemonic,
  });

  @override
  _ChooseOptionScreenState createState() => _ChooseOptionScreenState();
}

class _ChooseOptionScreenState extends State<ChooseOptionScreen> {
  bool _isLoading = false;

  Future<void> _onRegisteredPressed() async {
    setState(() => _isLoading = true);
    try {
      final mnemonic = await widget.generateMnemonic();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SeedPhraseScreen(
            mnemonic: mnemonic,
            email: widget.email,
            password: widget.password,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to generate mnemonic: $e',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onLoginWithMnemonicPressed() async {
    // final mnemonic = await widget.generateMnemonic();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MnemonicScreen(
          email: widget.email,
          password: widget.password,
          // mnemonic: mnemonic,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        appBar: AppBar(
          backgroundColor: surfaceColor.value,
          foregroundColor: primaryTextColor.value,
          elevation: 0,
          title: Text(
            'Choose an Option',
            style: TextStyle(
              color: Colors.white,
            ),
          ),
          centerTitle: true,
          leading: GestureDetector(
            onTap: () {
              Get.back();
            },
            child: Icon(
              Icons.arrow_back,
              color: Colors.white,
            ),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                spacing: 16,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Already have a mnemonic? Log in using your mnemonic, or proceed to generate a new one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  PrimaryButton(
                    text: "Enter Seed Phrase",
                    onTap: () {
                      _onLoginWithMnemonicPressed();
                    },
                    isLoading: _isLoading,
                  ),
                  PrimaryButton(
                    text: "Generate Seed Phrase",
                    onTap: () {
                      _onRegisteredPressed();
                    },
                    isLoading: _isLoading,
                    loadingText: 'Generating...',
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
