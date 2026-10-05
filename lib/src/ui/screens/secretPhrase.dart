import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:signer/src/ui/widgets/primaryButton.dart';

import '../controllers/appController.dart';
import '../theme/app_Text_Styles.dart';
import '../theme/colors.dart';

class SecretPhraseScreen extends StatefulWidget {
  final List<String> mnemonicPhrase;

  const SecretPhraseScreen({super.key, required this.mnemonicPhrase});

  @override
  State<SecretPhraseScreen> createState() => _SecretPhraseScreenState();
}

class _SecretPhraseScreenState extends State<SecretPhraseScreen> {
  final AppController _appController = Get.find<AppController>();

  int currentIndex = 0;
  bool _isPhraseRevealed = false;

  void _onNextPressed() {
    if (currentIndex < widget.mnemonicPhrase.length - 1) {
      // Show next word
      setState(() {
        currentIndex++;
      });
    } else {
      // Last word shown → pop screen
      Get.back();
      _appController.selectedBottomTabIndex.value = 0;
    }
  }

  void _showRevealDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: inputFieldBackgroundColor.value,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Reveal Secret Phrase',
            style: AppTextStyles.heading3.copyWith(color: primaryTextColor.value),
            textAlign: TextAlign.center,
          ),
          content: Text(
            'This will show your secret recovery phrase. Make sure you are in a private location and no one can see your screen.',
            style: AppTextStyles.body.copyWith(color: subTextColor.value),
            textAlign: TextAlign.center,
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      Get.back(); // Go back to previous screen
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: primaryTextColor.value.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Go Back',
                        style: AppTextStyles.body.copyWith(color: primaryTextColor.value),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _isPhraseRevealed = true;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: primaryColor.value,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Reveal Phrase',
                        style: AppTextStyles.body.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Show dialog when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showRevealDialog();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryBackgroundColor.value,
      body: SafeArea(
        bottom: false,
        child: SizedBox(
          width: Get.width,
          height: Get.height,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Your Recovery Phrase', style: AppTextStyles.heading1, textAlign: TextAlign.start),
                const SizedBox(height: 16),
                Text('Write it down and store it safely:', style: AppTextStyles.body, textAlign: TextAlign.start),
                const SizedBox(height: 32),
                // Only show phrase content if revealed
                if (_isPhraseRevealed) ...[
                /*Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children:
                      List.generate(widget.mnemonicPhrase.length, (index) {
                    final bool revealed = index <= currentIndex;

                    return SizedBox(
                      width: MediaQuery.of(context).size.width / 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: inputFieldBackgroundColor.value,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: inputFieldBorderColor.value),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('${index + 1}.',
                                style: AppTextStyles.body
                                    .copyWith(color: subTextColor.value)),
                            const SizedBox(width: 8),
                            // Expanded(
                            //     child: Text(widget.mnemonicPhrase[index],
                            //         style: AppTextStyles.heading3.copyWith(
                            //             color: primaryTextColor.value),
                            //     ),
                            // ),
                            Expanded(
                              child: Text(
                                // show the word only if revealed; otherwise show empty string
                                revealed ? widget.mnemonicPhrase[index] : '',
                                style: AppTextStyles.heading3
                                    .copyWith(color: primaryTextColor.value),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),*/
                // Show only the current word
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: inputFieldBackgroundColor.value,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: inputFieldBorderColor.value),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${currentIndex + 1}.',
                        style: AppTextStyles.body.copyWith(color: subTextColor.value),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.mnemonicPhrase[currentIndex],
                        style: AppTextStyles.heading2.copyWith(color: primaryTextColor.value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // PrimaryButton(
                //     text: 'I have backed it up', onTap: () => Get.back()),
                PrimaryButton(text: currentIndex == widget.mnemonicPhrase.length - 1 ? 'I have backed it up' : 'Next', onTap: _onNextPressed),
                const SizedBox(height: 16),
                // Copy to Clipboard button
                // GestureDetector(
                //   onTap: copyToClipboard,
                //   child: Container(
                //     width: double.infinity,
                //     padding: const EdgeInsets.symmetric(
                //         horizontal: 16, vertical: 12),
                //     decoration: BoxDecoration(
                //       border: Border.all(
                //           color: primaryTextColor.value.withOpacity(0.3)),
                //       borderRadius: BorderRadius.circular(10),
                //     ),
                //     child: Row(
                //       spacing: 8,
                //       mainAxisSize: MainAxisSize.min,
                //       mainAxisAlignment: MainAxisAlignment.center,
                //       children: [
                //         Icon(
                //           Icons.copy,
                //           size: 20,
                //           color: primaryTextColor.value,
                //         ),
                //         Text(
                //           "Copy To Clipboard",
                //           style: AppTextStyles.body
                //               .copyWith(color: primaryTextColor.value),
                //         ),
                //       ],
                //     ),
                //   ),
                // ),
                ] else ...[
                  // Show placeholder when phrase is not revealed
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
                    decoration: BoxDecoration(
                      color: inputFieldBackgroundColor.value,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: inputFieldBorderColor.value),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.visibility_off,
                          size: 48,
                          color: subTextColor.value,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Phrase Hidden',
                          style: AppTextStyles.heading3.copyWith(color: subTextColor.value),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap "Reveal Phrase" in the dialog to view your recovery phrase',
                          style: AppTextStyles.body.copyWith(color: subTextColor.value),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
