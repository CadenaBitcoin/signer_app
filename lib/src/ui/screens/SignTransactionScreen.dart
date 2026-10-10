import 'dart:async';
import 'dart:convert';

import 'package:bip39/bip39.dart' as bip39;
import 'package:dlc_wallet/dlc_wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signer/models/sigReqsByDlcIdsModel.dart';
import 'package:signer/models/userOfferDlcPollModel.dart' as userOfferDlcPollModel;
import 'package:signer/services/auto_signing_service.dart';
import 'package:signer/services/dataService/apiService.dart';
import 'package:signer/services/storage_service.dart';
import 'package:signer/src/ui/controllers/appController.dart';
import 'package:signer/src/ui/theme/colors.dart';
import 'package:signer/src/ui/widgets/primaryButton.dart';

class SignTransactions extends StatefulWidget {
  // final List<Payload> payloads;

  const SignTransactions({super.key});

  @override
  State<SignTransactions> createState() => _SignTransactionsState();
}

class _SignTransactionsState extends State<SignTransactions> with WidgetsBindingObserver {
  ApiService apiService = ApiService();
  AppController appController = Get.find<AppController>();
  final AutoSigningService autoSigningService = Get.find<AutoSigningService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initial poll to load data
    // apiService.userOfferDlcIdsPoll("offer_dlc");
    _checkToken();
  }

  Future<void> _checkToken() async {
    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwtToken');
    debugPrint("JWT token inside SignTransactionScreen : $jwtToken");

    if (jwtToken != null && jwtToken.isNotEmpty) {
      // ✅ Token exists → call API
      apiService.userOfferDlcIdsPoll("offer_dlc");
    } else {
      // ❌ Token missing → do nothing
      debugPrint("JWT token not found inside SignTransactionScreen. Skipping API call.");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Resume polling when app comes back to foreground
      autoSigningService.resumePolling();
    } else if (state == AppLifecycleState.paused) {
      // Optionally pause polling when app goes to background to save resources
      // autoSigningService.pausePolling();
    }
  }

  void _manualSign() async {
    // Get filtered DLCs (only those that need signing)
    final filteredDlcs = await _getFilteredDlcs();

    if (filteredDlcs.isEmpty) {
      Get.snackbar(
        'Info',
        'No DLCs available for signing.',
        backgroundColor: Colors.blue,
        colorText: Colors.white,
        duration: Duration(seconds: 3),
      );
      return;
    }

    // Use the first filtered DLC (one that actually needs signing)
    final dlcId = filteredDlcs[0].dlcId ?? "";
    if (dlcId.isEmpty) {
      Get.snackbar(
        'Error',
        'No DLC ID available for signing.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
      );
      return;
    }

    print('ManualSign: Attempting to sign DLC: $dlcId');
    print('ManualSign: DLC status: ${filteredDlcs[0].status}');
    print('ManualSign: DLC initiator: ${filteredDlcs[0].iniEmail}');
    print('ManualSign: DLC acceptor: ${filteredDlcs[0].accEmail}');

    final result = await ApiService().sigReqsByDlcIds([dlcId]);
    if (result == "OK") {
      if (appController.sigReqsByDlcIdsModelObject.value.payload!.isNotEmpty) {
        await signFundingInput(dlcId: dlcId, inputReqs: appController.sigReqsByDlcIdsModelObject.value.payload?[0].funding?.inputReqs);
      } else {
        Get.snackbar(
          'Error',
          'No signature requests found for this DLC.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: Duration(seconds: 4),
        );
      }
    } else {
      Get.snackbar(
        'Error',
        'Failed to fetch signature requests.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: primaryBackgroundColor.value,
        appBar: AppBar(backgroundColor: primaryBackgroundColor.value, title: Text("Transactions", style: TextStyle(color: Colors.white))),
        body: SafeArea(
          bottom: false,
          child: SizedBox(
            height: Get.height,
            width: Get.width,
            child: Column(
              children: [
                // Auto-signing status indicator
                Obx(() => Container(
                      margin: EdgeInsets.all(16),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: autoSigningService.isAutoSigningEnabled.value ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: autoSigningService.isAutoSigningEnabled.value ? Colors.green : Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            autoSigningService.isAutoSigningEnabled.value ? Icons.auto_awesome : Icons.pause,
                            color: autoSigningService.isAutoSigningEnabled.value ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  autoSigningService.isAutoSigningEnabled.value
                                      ? "Auto-signing enabled - Monitoring for new contracts..."
                                      : "Manual mode - You will be notified of new contracts",
                                  style: TextStyle(
                                    color: autoSigningService.isAutoSigningEnabled.value ? Colors.green : Colors.orange,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (autoSigningService.isAutoSigningEnabled.value && autoSigningService.lastProcessedTime.value != DateTime.now())
                                  Text(
                                    "Last processed: ${_formatTime(autoSigningService.lastProcessedTime.value)}",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                Expanded(
                  child: FutureBuilder<List<userOfferDlcPollModel.Payload>>(
                    future: _getFilteredDlcs(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }

                      final filteredDlcs = snapshot.data ?? [];

                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredDlcs.length,
                        itemBuilder: (context, index) {
                          final payload = filteredDlcs[index];

                          return Card(
                            color: primaryColor.value.withOpacity(0.1),
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildTextRow("DLC ID", payload?.dlcId ?? ""),
                                  _buildTextRow("Temp Contract ID", payload?.tmpCntrId ?? ""),
                                  _buildTextRow("Initiator Role", payload?.iniRole ?? ""),
                                  _buildTextRow("Initiator Email", payload?.iniEmail ?? ""),
                                  _buildTextRow("Acceptor Email", payload?.accEmail ?? ""),
                                  _buildTextRow("Oracle ID", payload?.orclId ?? ""),
                                  _buildTextRow("Status", payload?.status ?? ""),
                                  _buildTextRow("Interest", payload?.interest?.toString() ?? ""),
                                  _buildTextRow("Interest Earning", payload?.interestEar?.toString() ?? ""),
                                  _buildTextRow("Initiator Collateral", payload?.iniCollateralSats?.toString() ?? ""),
                                  _buildTextRow("Acceptor Collateral", payload?.accCollateralSats?.toString() ?? ""),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          loadingText: "Processing",
                          isLoading: appController.sigReqsByDlcIdsModelLoader.value ||
                              appController.offerDlcSignaturesLoader.value ||
                              autoSigningService.isProcessing.value,
                          onTap: _manualSign,
                          text: "Manual Sign",
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Obx(() => PrimaryButton(
                              loadingText: "Processing",
                              isLoading: appController.sigReqsByDlcIdsModelLoader.value ||
                                  appController.offerDlcSignaturesLoader.value ||
                                  autoSigningService.isProcessing.value,
                              onTap: () => autoSigningService.toggleAutoSigning(!autoSigningService.isAutoSigningEnabled.value),
                              text: autoSigningService.isAutoSigningEnabled.value ? "Auto Sign Off" : "Auto Sign On",
                            )),
                      ),
                    ],
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

  Future signFundingInput({
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

        final mnemonic = await getMnemonic(storedEmail);
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
        await DlcWallet.initWithEntropy(entropy, appController.currentEnvironment);
      }

      // Collect all funding signatures
      List<String> fundingSignatures = [];

      for (final req in inputReqs!) {
        final hash = req.sighash;
        final signerIndex = req.signerIndex;
        final signerIndex4 = req.signerIndex4;
        final signerPubkey = req.signerPubkey;

        if (hash == null || signerIndex == null || signerIndex4 == null || signerPubkey == null) {
          throw Exception('Invalid signature request parameters');
        }

        print('hash: $hash');
        final signature = await DlcWallet.signHashEcdsa(hash, signerIndex, signerIndex4, signerPubkey);
        print('ECDSA Signature: $signature');
        fundingSignatures.add(signature);
      }

      // Get refund signature
      String refundSignature = '';
      final refundReqs = appController.sigReqsByDlcIdsModelObject.value.payload![0].refund?.inputReqs;
      if (refundReqs != null && refundReqs.isNotEmpty) {
        final refundReq = refundReqs[0];
        if (refundReq.sighash != null && refundReq.signerIndex != null && refundReq.signerIndex4 != null && refundReq.signerPubkey != null) {
          refundSignature = await DlcWallet.signHashEcdsa(refundReq.sighash!, refundReq.signerIndex!, signerIndex4!, refundReq.signerPubkey!);
          print('Refund Signature: $refundSignature');
        }
      }

      // Get adaptor signature points
      String adaptorSigPoints = '';
      final cets = appController.sigReqsByDlcIdsModelObject.value.payload![0].cets;
      if (cets != null && cets.intervalWildcards != null && cets.intervalWildcards!.isNotEmpty) {
        try {
          // Parse the string parameters into lists
          final noncesList = cets.nonces?.split(' ').where((s) => s.isNotEmpty).toList() ?? [];
          final intervalWildcardsList = cets.intervalWildcards?.split(' ').where((s) => s.isNotEmpty).toList() ?? [];
          final sighashesList = cets.sighashes?.split(' ').where((s) => s.isNotEmpty).toList() ?? [];

          print('Raw CET Parameters:');
          print('  numDigits: ${cets.numDigits}');
          print('  numCets: ${cets.numCets}');
          print('  digitStringTemplate: ${cets.digitStringTemplate}');
          print('  nonces string: "${cets.nonces}"');
          print('  intervalWildcards string: "${cets.intervalWildcards}"');
          print('  sighashes string: "${cets.sighashes}"');
          print('  nonces length: ${noncesList.length}');
          print('  intervalWildcards length: ${intervalWildcardsList.length}');
          print('  sighashes length: ${sighashesList.length}');

          // Debug: Show first few items of each list
          if (noncesList.isNotEmpty) {
            print('  First 3 nonces: ${noncesList.take(3).toList()}');
          }
          if (intervalWildcardsList.isNotEmpty) {
            print('  First 3 intervalWildcards: ${intervalWildcardsList.take(3).toList()}');
          }
          if (sighashesList.isNotEmpty) {
            print('  First 3 sighashes: ${sighashesList.take(3).toList()}');
          }

          if (noncesList.isEmpty) {
            print('No CET parameters provided');
            throw Exception('No CET parameters provided');
          }

          // Validate that we have the required CET parameters
          if (cets.signerIndex == null || cets.signerIndex4 == null || cets.signerPubkey == null || cets.oraclePubkey == null) {
            print(
                'Missing required CET parameters: signerIndex=${cets.signerIndex}, signerIndex4=${cets.signerIndex4}, signerPubkey=${cets.signerPubkey}, oraclePubkey=${cets.oraclePubkey}');
            throw Exception('Missing required CET parameters');
          }

          // Validate that the parameter lists have the expected lengths
          if (noncesList.length != intervalWildcardsList.length || noncesList.length != sighashesList.length) {
            print(
                'CET parameter length mismatch: nonces=${noncesList.length}, intervalWildcards=${intervalWildcardsList.length}, sighashes=${sighashesList.length}');
            print('This suggests the parsing of space-separated strings may be incorrect.');
            print('Expected all lists to have the same length.');

            // Try alternative parsing if the lengths don't match
            if (noncesList.length == 1 && intervalWildcardsList.length > 1) {
              print('Attempting alternative parsing - nonces might be a single value repeated');
              // If nonces is a single value, we might need to repeat it for each CET
              final singleNonce = noncesList[0];
              final repeatedNonces = List<String>.filled(intervalWildcardsList.length, singleNonce);

              print('Using repeated nonce: $singleNonce for ${intervalWildcardsList.length} CETs');

              // Validate that the parameter lists have the expected lengths
              if (repeatedNonces.length != intervalWildcardsList.length || repeatedNonces.length != sighashesList.length) {
                throw Exception('CET parameter length mismatch after alternative parsing');
              }

              // Use CET-specific parameters instead of funding parameters
              final signatures = await DlcWallet.createCetAdaptorSigs(
                numDigits: cets.numDigits ?? 2,
                numCets: cets.numCets ?? intervalWildcardsList.length,
                digitStringTemplate: cets.digitStringTemplate ?? 'BTCUSD',
                oraclePublicKey: cets.oraclePubkey!,
                signingKeyIndex: cets.signerIndex!,
                signingKeyIndex4: cets.signerIndex4!,
                signingPublicKey: cets.signerPubkey!,
                nonces: repeatedNonces,
                intervalWildcards: intervalWildcardsList,
                sighashes: sighashesList,
              );

              adaptorSigPoints = signatures.join(' '); // Space-separated signatures
              print('Adaptor Signature Points: $adaptorSigPoints');
            } else if (noncesList.length > 1 && intervalWildcardsList.length > noncesList.length) {
              print('Using original ${noncesList.length} nonces for ${intervalWildcardsList.length} CETs');
              print('The DlcWallet function will handle the nonce cycling internally');

              // Use the original 7 nonces - let the DlcWallet function handle the cycling
              final signatures = await DlcWallet.createCetAdaptorSigs(
                numDigits: cets.numDigits ?? 2,
                numCets: cets.numCets ?? intervalWildcardsList.length,
                digitStringTemplate: cets.digitStringTemplate ?? 'BTCUSD',
                oraclePublicKey: cets.oraclePubkey!,
                signingKeyIndex: cets.signerIndex!,
                signingKeyIndex4: cets.signerIndex4!,
                signingPublicKey: cets.signerPubkey!,
                nonces: noncesList, // Use original 7 nonces
                intervalWildcards: intervalWildcardsList,
                sighashes: sighashesList,
              );

              adaptorSigPoints = signatures.join(' '); // Space-separated signatures
              print('Adaptor Signature Points: $adaptorSigPoints');
            } else {
              throw Exception('CET parameter length mismatch');
            }
          } else {
            // Use CET-specific parameters instead of funding parameters
            final signatures = await DlcWallet.createCetAdaptorSigs(
              numDigits: cets.numDigits ?? 2,
              numCets: cets.numCets ?? intervalWildcardsList.length,
              digitStringTemplate: cets.digitStringTemplate ?? 'BTCUSD',
              oraclePublicKey: cets.oraclePubkey!,
              signingKeyIndex: cets.signerIndex!,
              signingKeyIndex4: cets.signerIndex4!,
              signingPublicKey: cets.signerPubkey!,
              nonces: noncesList,
              intervalWildcards: intervalWildcardsList,
              sighashes: sighashesList,
            );

            adaptorSigPoints = signatures.join(' '); // Space-separated signatures
            print('Generated ${signatures.length} CET adaptor signatures');
            print('Adaptor Signature Points: $adaptorSigPoints');
          }
        } catch (e) {
          print('Error creating CET adaptor signatures: $e');

          // Ask user if they want to continue without CET signatures
          final shouldContinue = await Get.dialog<bool>(
            AlertDialog(
              title: Text('CET Signature Error'),
              content:
                  Text('Failed to generate CET signatures: ${e.toString()}\n\nWould you like to continue with funding and refund signatures only?'),
              actions: [
                TextButton(
                  onPressed: () => Get.back(result: false),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Get.back(result: true),
                  child: Text('Continue'),
                ),
              ],
            ),
          );

          if (shouldContinue != true) {
            return; // User cancelled
          }

          // Get.snackbar(
          //   'Warning',
          //   'Continuing with funding and refund signatures only.',
          //   backgroundColor: Colors.orange,
          //   colorText: Colors.white,
          //   duration: Duration(seconds: 3),
          // );
          // Continue without adaptor signatures
        }
      }

      // Call API with all parameters
      print('Submitting signatures to API:');
      print('  DLC ID: $dlcId');
      print('  Funding signatures count: ${fundingSignatures.length}');
      print('  Funding signatures: ${fundingSignatures.join(' ')}');
      print('  Refund signature: $refundSignature');
      print('  Adaptor signature points: $adaptorSigPoints');

      final result = await ApiService().offerDlcSignatures(
          dlc_id: '$dlcId', funding_sigs: fundingSignatures.join(' '), refund_sig: refundSignature, adaptor_sig_points: adaptorSigPoints);

      if (result == 'OK') {
        // Show success message with details from the response
        final responseMessage = appController.dlcSignatureResponseObject.value.message ?? 'DLC signatures submitted successfully!';
        Get.snackbar(
          'Success',
          responseMessage,
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: Duration(seconds: 2),
        );

        // Refresh the DLC list to show updated status
        await apiService.userOfferDlcIdsPoll("offer_dlc");
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
            // Check if it's a CET signature error
            final responseDetail = appController.dlcSignatureResponseObject.value.detail;
            if (responseDetail != null && responseDetail.contains('Invalid CET signatures')) {
              errorMessage = 'CET signature validation failed. Please check the contract parameters and try again.';
            } else {
              errorMessage = 'Server error occurred. Please try again later.';
            }
            break;
          case 'FAILED':
          default:
            errorMessage = 'Failed to submit DLC signatures. Please try again.';
            break;
        }

        Get.snackbar(
          'Error',
          errorMessage,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: Duration(seconds: 4),
        );
      }
    } catch (e) {
      print('Error in signFundingInput: $e');
      Get.snackbar(
        'Error',
        'An error occurred while signing transactions: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: Duration(seconds: 4),
      );
    }
  }

  Widget _buildTextRow(String label, String? value) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text("$label: ${value ?? '-'}", style: const TextStyle(fontSize: 14, color: Colors.white)));
  }

  final _storage = const FlutterSecureStorage();

  Future<String?> getMnemonic(String email) async {
    final _storage = const FlutterSecureStorage();

    final userKey = 'user_$email';

    final storedData = await _storage.read(key: userKey);
    if (storedData == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(storedData);
    return decoded['mnemonic'] as String?;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  /// Filter DLCs based on user role and status
  /// Implements the same logic as the auto-signing service
  Future<List<userOfferDlcPollModel.Payload>> _getFilteredDlcs() async {
    final allDlcs = appController.userOfferDlcIdsPollObject.value.payload ?? [];
    final userEmail = await StorageService.getLoggedInEmail();

    if (userEmail == null) {
      print('SignTransactionScreen: Could not determine user email');
      return [];
    }

    final filteredDlcs = <userOfferDlcPollModel.Payload>[];

    for (final dlc in allDlcs) {
      final status = dlc.status;
      bool needsSignature = false;

      if (status == 'offer_dlc') {
        // Always needs signature for offer_dlc
        needsSignature = true;
        print('SignTransactionScreen: DLC ${dlc.dlcId} needs signature (offer_dlc)');
      } else {
        // Check user role and status
        final userRole = _determineUserRole(dlc, userEmail);

        if (status == 'sign_acc' && userRole == 'ini') {
          // Initiator needs to sign when acceptor has signed
          needsSignature = true;
          print('SignTransactionScreen: DLC ${dlc.dlcId} needs signature (initiator for sign_acc)');
        } else if (status == 'sign_ini' && userRole == 'acc') {
          // Acceptor needs to sign when initiator has signed
          needsSignature = true;
          print('SignTransactionScreen: DLC ${dlc.dlcId} needs signature (acceptor for sign_ini)');
        } else {
          print('SignTransactionScreen: DLC ${dlc.dlcId} does not need signature (role: $userRole, status: $status)');
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
}
