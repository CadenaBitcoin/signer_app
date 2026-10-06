import 'dart:math';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip32/bip32.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:signer/services/bitcoin_wallet_creation.dart';
import 'package:signer/services/storage_service.dart';
import 'package:signer/src/ui/controllers/appController.dart';
import 'package:signer/src/ui/widgets/bottomNavbar.dart';

import '../../theme/colors.dart';
import '../../widgets/primaryButton.dart';

class ConfirmSeedPhraseScreen extends StatefulWidget {
  final String? fromPage;

  final String mnemonic;
  final String email;
  final String password;

  const ConfirmSeedPhraseScreen({
    super.key,
    required this.mnemonic,
    required this.email,
    required this.password,
    this.fromPage,
  });
  @override
  State<ConfirmSeedPhraseScreen> createState() =>
      _ConfirmSeedPhraseScreenState();
}

class _ConfirmSeedPhraseScreenState extends State<ConfirmSeedPhraseScreen> {
  AppController appController = Get.find<AppController>();
  late List<String> mnemonicWords;
  late List<int> confirmIndices;
  late List<String?> selectedWords;
  late List<String> options;

  var privateKeyHex = ''.obs;
  var publicKeyHex = ''.obs;
  var address = ''.obs;
  var path = ''.obs;
  var xPub = ''.obs;

  @override
  void initState() {
    super.initState();
    mnemonicWords = widget.mnemonic.trim().split(' ');
    confirmIndices = _generateRandomIndices(3, max: mnemonicWords.length);
    selectedWords = List<String?>.filled(confirmIndices.length, null);

    Set<String> tempOptions =
        confirmIndices.map((i) => mnemonicWords[i]).toSet();
    while (tempOptions.length < 5) {
      String randomWord = mnemonicWords[Random().nextInt(mnemonicWords.length)];
      tempOptions.add(randomWord);
    }

    options = tempOptions.toList()..shuffle();
  }

  List<int> _generateRandomIndices(int count, {required int max}) {
    final rand = Random();
    final Set<int> indices = {};
    while (indices.length < count) {
      indices.add(rand.nextInt(max));
    }
    return indices.toList();
  }

  void _onWordTap(String word) {
    int index = selectedWords.indexWhere((w) => w == null);
    if (index != -1) {
      setState(() {
        selectedWords[index] = word;
        options.remove(word);
      });
    }
  }

  void _removeSelected(int index) {
    final word = selectedWords[index];
    if (word != null) {
      setState(() {
        options.add(word);
        selectedWords[index] = null;
        options.shuffle();
      });
    }
  }

  void _verify() async {
    if (widget.fromPage == "import_wallet") {
      appController.xpubValidationObject.value.payload = true;
    } else {
      appController.userUpgradeLoader.value = true;
    }
    print("---------------------------");

    bool correct = true;
    for (int i = 0; i < confirmIndices.length; i++) {
      final expected = mnemonicWords[confirmIndices[i]];
      final selected = selectedWords[i];
      if (selected != expected) {
        correct = false;
        break;
      }
    }

    if (correct) {
      print("---------------------------");

      final seed = bip39.mnemonicToSeed(widget.mnemonic);
      // final testnet = bip32.NetworkType(
      //   bip32: bip32.Bip32Type(
      //     public: 0x043587cf, // tpub
      //     private: 0x04358394, // testnet private
      //   ),
      //   wif: 0xEF, // ✅ required for private key encoding
      // );

      // Use current network configuration from AppController
      final root = BIP32.fromSeed(seed, appController.currentNetworkType);

      final account = root.derivePath(appController.currentDerivationPath);
      final xpub = account.neutered().toBase58();
      final child = account.derivePath("0/0"); // <-- very important

      final pubkey = child.publicKey;

      // print('Bech32 Mainnet Address: ${address.address}');

      final privKey = child.privateKey!;
      // final pubKey = child.publicKey;

      // 👇 Replace manual logic with helper function
      final address = generateP2WPKHAddress(pubkey, isTestnet: appController.isTestnet);

      // print("pubKey: ${pubKey}");

      // ✅ Save to SharedPreferences

      if (widget.fromPage == "import_wallet") {
        print("==============import wallet");
        // ApiService().xpubValidation(xpub: xpub).then((onValue) async {
        // if (appController.xpubValidationObject.value.payload == true) {
        await StorageService.saveWalletData(
          email: widget.email,
          password: widget.password,
          mnemonic: widget.mnemonic,
          address: '',
          privateKey: privateKeyHex.value,
          xpub: xpub,
        );
        await StorageService.setLoginStatus(true);

        /// 👇 give time for loading state to show
        await Future.delayed(const Duration(seconds: 1));

        appController.userUpgradeLoader.value = false;
        Get.offAll(() => BottomNavBar());
        // }
        // });
      } else {
        // ApiService().userUpgradePubx(xpub: "${xpub}").then((onValue) async {
        await StorageService.saveWalletData(
          email: widget.email,
          password: widget.password,
          mnemonic: widget.mnemonic,
          address: '',
          privateKey: privateKeyHex.value,
          xpub: xpub,
        );
        // Add this line to set isLoggedIn to true
        await StorageService.setLoginStatus(true);

        /// 👇 give time for loading state to show
        await Future.delayed(const Duration(seconds: 1));

        appController.userUpgradeLoader.value = false;

        Get.offAll(BottomNavBar());
        //   builder:
        //       (_) => AlertDialog(
        //         backgroundColor: cardBgColor.value,
        //
        //         titleTextStyle: TextStyle(
        //           color: primaryTextColor.value,
        //           fontSize: 18,
        //           fontWeight: FontWeight.bold,
        //         ),
        //         contentTextStyle: TextStyle(color: secondaryTextColor.value),
        //         title: Text(correct ? "✅ Success" : "❌ Failed"),
        //         content: Obx(
        //           () => Column(
        //             mainAxisSize: MainAxisSize.min,
        //             crossAxisAlignment: CrossAxisAlignment.start,
        //             children: [
        //               Text(
        //                 correct
        //                     ? "Seed phrase confirmed successfully!"
        //                     : "Incorrect words. Please try again.",
        //               ),
        //               const SizedBox(height: 16),
        //               Text("privateKey: ${privKey}"),
        //               const SizedBox(height: 16),
        //               Text("publicKey: ${pubkey}"),
        //               const SizedBox(height: 16),
        //               Text("Address: ${address}"),
        //               const SizedBox(height: 16),
        //               Text("Xpath: ${path.value}"),
        //               const SizedBox(height: 16),
        //               Text("XPub.value: ${xpub}"),
        //               const SizedBox(height: 16),
        //             ],
        //           ),
        //         ),
        //
        //         actions: [
        //           TextButton(
        //             onPressed: () {
        //               Get.offAll(BottomNavBar());
        //               // Get.to(QrScanner());
        //             },
        //             child: Text(
        //               "OK",
        //               style: TextStyle(color: primaryColor.value),
        //             ),
        //           ),
        //         ],
        //       ),
        // );
        // }
        // );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        appBar: AppBar(
          title: const Text("Confirm Seed Phrase"),
          backgroundColor: surfaceColor.value,
          foregroundColor: primaryTextColor.value,
          elevation: 0,
        ),
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Select the correct words for these positions:",
                  style: TextStyle(
                    color: primaryTextColor.value,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(confirmIndices.length, (i) {
                    return GestureDetector(
                      onTap: () => _removeSelected(i),
                      child: Container(
                        width: 100,
                        height: 60,
                        decoration: BoxDecoration(
                          color: selectedWords[i] == null
                              ? surfaceColor.value
                              : successColor.value.withOpacity(0.2),
                          border: Border.all(color: borderColor.value),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          selectedWords[i] ?? 'Word ${confirmIndices[i] + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selectedWords[i] == null
                                ? hintTextColor.value
                                : successColor.value,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 32),
                Text(
                  "Tap the correct words:",
                  style: TextStyle(color: subTextColor.value),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: options.map((word) {
                    return ElevatedButton(
                      onPressed: () => _onWordTap(word),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: inputFieldBackgroundColor.value,
                        foregroundColor: primaryTextColor.value,
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      child: Text(word),
                    );
                  }).toList(),
                ),
                const Spacer(),
                PrimaryButton(
                  text: "Verify",
                  onTap: () {
                    if (!selectedWords.contains(null)) {
                      _verify();
                    }
                  },
                  isLoading: appController.userUpgradeLoader.value,
                  loadingText: "Processing...",
                ),
                const SizedBox(height: 24),
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
