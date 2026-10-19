import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:signer/src/ui/controllers/appController.dart';

import '../../../services/bitcoin_wallet_creation.dart';
import '../../../services/storage_service.dart';
import '../theme/colors.dart';
import '../widgets/appTextField.dart';
import '../widgets/bottomNavbar.dart';
import '../widgets/primaryButton.dart';

class MnemonicScreen extends StatefulWidget {
  final String email;
  final String password;
  // final String mnemonic;

  const MnemonicScreen({
    super.key,
    required this.email,
    required this.password,
    // required this.mnemonic,
  });

  @override
  State<MnemonicScreen> createState() => _MnemonicScreenState();
}

class _MnemonicScreenState extends State<MnemonicScreen> {
  final List<TextEditingController> _wordControllers = List.generate(
    12, 
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    12, 
    (index) => FocusNode(),
  );
  bool _isVerifying = false;
  final appController = Get.find<AppController>();

  @override
  void dispose() {
    for (var controller in _wordControllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    // Combine all words with single spaces
    final List<String> words = _wordControllers
        .map((controller) => controller.text.trim())
        .where((word) => word.isNotEmpty)
        .toList();

    print('words count -> ${words.length}');
    
    if (words.length != 12) {
      Get.snackbar(
        "Error",
        "Please enter all 12 words",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
      return;
    }
    
    final enteredMnemonic = words.join(' ');
    if (!bip39.validateMnemonic(enteredMnemonic)) {
      Get.snackbar(
        "Error",
        "Invalid mnemonic. Please check again.",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    try {
      setState(() => _isVerifying = true);
      final seed = bip39.mnemonicToSeed(enteredMnemonic);
      
      // Use current network configuration from AppController
      final root = bip32.BIP32.fromSeed(seed, appController.currentNetworkType);
      final account = root.derivePath(appController.currentDerivationPath);
      final xpub = account.neutered().toBase58();
      final child = account.derivePath("0/0");

      final pubkey = child.publicKey;
      final privKey = child.privateKey!;
      final address = generateP2WPKHAddress(pubkey, isTestnet: appController.isTestnet);

      await StorageService.saveWalletData(
        email: widget.email,
        password: widget.password,
        mnemonic: enteredMnemonic,
        address: address,
        privateKey: privKey.toString(),
        xpub: xpub,
      );
      await StorageService.setLoginStatus(true);

      setState(() => _isVerifying = false);

      Get.offAll(() => BottomNavBar());
    } catch (e) {
      setState(() => _isVerifying = false);
      Get.snackbar(
        "Error",
        "Something went wrong: $e",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: Duration(seconds: 4),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ListView(
              // mainAxisAlignment: MainAxisAlignment.center,
              // crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "Enter Your Seed Phrase",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "Type the exact 12 words of your mnemonic.\nMake sure they are in the correct order.",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Grid of 12 text fields for mnemonic words (2 per column)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 3.5,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    return Row(
                      children: [
                        // Number on the left
                        Container(
                          width: 24,
                          alignment: Alignment.center,
                          child: Text(
                            '${index + 1}.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Text field
                        Expanded(
                          child: AppTextField(
                            controller: _wordControllers[index],
                            hintText: "word ${index + 1}",
                            enablePaste: false,
                            inputFormatters: [
                              // Prevent spaces from being entered
                              FilteringTextInputFormatter.deny(RegExp(r'\s')),
                              // Prevent paste operations
                              NoPasteFormatter(),
                            ],
                            onChange: (value) {
                              // Auto-focus next field when current field is filled
                              if (value.isNotEmpty && index < 11) {
                                _focusNodes[index + 1].requestFocus();
                              }
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 50),
                Text(
                  "⚠️ Keep your mnemonic safe. Anyone with this phrase can access your wallet.",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.redAccent.shade100,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  text: "Verify",
                  onTap: _verify,
                  isLoading: _isVerifying,
                  loadingText: 'Verifying...',
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
