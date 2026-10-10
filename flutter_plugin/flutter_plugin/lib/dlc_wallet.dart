import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

// Define the C function signatures
typedef InitWithEntropyC = Pointer<Utf8> Function(
    Pointer<Utf8> entropy, Pointer<Utf8> network);
typedef InitWithEntropyCDart = Pointer<Utf8> Function(
    Pointer<Utf8> entropy, Pointer<Utf8> network);

typedef InitFromFileC = Pointer<Utf8> Function(
    Pointer<Utf8> path, Pointer<Utf8> password);
typedef InitFromFileCDart = Pointer<Utf8> Function(
    Pointer<Utf8> path, Pointer<Utf8> password);

typedef GetXpubC = Pointer<Utf8> Function();
typedef GetXpubCDart = Pointer<Utf8> Function();

typedef GetPublicKeyC = Pointer<Utf8> Function(Uint32 index);
typedef GetPublicKeyCDart = Pointer<Utf8> Function(int index);

typedef GetAddressC = Pointer<Utf8> Function(Uint32 index);
typedef GetAddressCDart = Pointer<Utf8> Function(int index);

typedef SignHashEcdsaC = Pointer<Utf8> Function(
    Pointer<Utf8> hash, Uint32 signerIndex, Pointer<Utf8> signerPubkey);
typedef SignHashEcdsaCDart = Pointer<Utf8> Function(
    Pointer<Utf8> hash, int signerIndex, Pointer<Utf8> signerPubkey);

typedef CreateDeterministicNonceC = Pointer<Utf8> Function(
    Pointer<Utf8> eventId, Uint32 index);
typedef CreateDeterministicNonceCDart = Pointer<Utf8> Function(
    Pointer<Utf8> eventId, int index);

typedef CreateCetAdaptorSigsC = Pointer<Utf8> Function(
    Uint8 numDigits,
    Uint32 numCets,
    Pointer<Utf8> digitStringTemplate,
    Pointer<Utf8> oraclePublicKey,
    Uint32 signingKeyIndex,
    Pointer<Utf8> signingPublicKey,
    Pointer<Utf8> nonces,
    Pointer<Utf8> intervalWildcards,
    Pointer<Utf8> sighashes);
typedef CreateCetAdaptorSigsCDart = Pointer<Utf8> Function(
    int numDigits,
    int numCets,
    Pointer<Utf8> digitStringTemplate,
    Pointer<Utf8> oraclePublicKey,
    int signingKeyIndex,
    Pointer<Utf8> signingPublicKey,
    Pointer<Utf8> nonces,
    Pointer<Utf8> intervalWildcards,
    Pointer<Utf8> sighashes);

typedef FreeCStringC = Void Function(Pointer<Utf8> s);
typedef FreeCStringCDart = void Function(Pointer<Utf8> s);

class DlcWallet {
  static DynamicLibrary? _lib;
  static late final InitWithEntropyCDart _initWithEntropy;
  // static late final InitFromFileCDart _initFromFile;
  static late final GetXpubCDart _getXpub;
  static late final GetPublicKeyCDart _getPublicKey;
  static late final GetAddressCDart _getAddress;
  static late final SignHashEcdsaCDart _signHashEcdsa;
  static late final CreateDeterministicNonceCDart _createDeterministicNonce;
  static late final CreateCetAdaptorSigsCDart _createCetAdaptorSigs;
  static late final FreeCStringCDart _freeCString;
  
  // Method channel for iOS
  static const MethodChannel _channel = MethodChannel('dlc_wallet');

  static void _loadLibrary() {
    if (_lib != null) return;

    try {
      if (Platform.isAndroid) {
        _lib = DynamicLibrary.open('libdlcplazacryptlib.so');
      } else if (Platform.isIOS) {
        _lib = DynamicLibrary.process();
      } else if (Platform.isLinux) {
        _lib = DynamicLibrary.open('libdlcplazacryptlib.so');
      } else if (Platform.isWindows) {
        _lib = DynamicLibrary.open('dlcplazacryptlib.dll');
      } else if (Platform.isMacOS) {
        _lib = DynamicLibrary.open('libdlcplazacryptlib.dylib');
      } else {
        throw UnsupportedError('Platform not supported');
      }

      if (_lib == null) {
        throw Exception('Failed to load native library: library is null');
      }

      // Load function pointers with proper error handling
      try {
        _initWithEntropy = _lib!
            .lookup<NativeFunction<InitWithEntropyC>>('init_with_entropy_c')
            .asFunction();
        // _initFromFile = _lib!
        //     .lookup<NativeFunction<InitFromFileC>>('init_from_file_c')
        //     .asFunction();
        _getXpub =
            _lib!.lookup<NativeFunction<GetXpubC>>('get_xpub_c').asFunction();
        _getPublicKey = _lib!
            .lookup<NativeFunction<GetPublicKeyC>>('get_public_key_c')
            .asFunction();
        _getAddress =
            _lib!.lookup<NativeFunction<GetAddressC>>('get_address_c').asFunction();
        _signHashEcdsa = _lib!
            .lookup<NativeFunction<SignHashEcdsaC>>('sign_hash_ecdsa_c')
            .asFunction();
        _createDeterministicNonce = _lib!
            .lookup<NativeFunction<CreateDeterministicNonceC>>(
                'create_deterministic_nonce_c')
            .asFunction();
        _createCetAdaptorSigs = _lib!
            .lookup<NativeFunction<CreateCetAdaptorSigsC>>(
                'create_cet_adaptor_sigs_c')
            .asFunction();
        _freeCString =
            _lib!.lookup<NativeFunction<FreeCStringC>>('free_cstring').asFunction();
      } catch (e) {
        throw Exception('Failed to load function pointers from native library: $e');
      }
    } catch (e) {
      throw Exception('Failed to initialize DLC wallet library: $e');
    }
  }

  static String _convertCStringAndFree(Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      throw Exception('Null pointer returned from native function');
    }

    final result = ptr.toDartString();
    _freeCString(ptr);

    if (result.startsWith('ERROR: ')) {
      throw Exception(result.substring(7));
    }

    return result;
  }

  // ==================== WALLET MANAGEMENT ====================

  /// Initialize wallet with entropy (hex string) and network
  /// Used for: Creating new wallets from seed phrases
  static Future<String> initWithEntropy(String entropy, String network) async {
    if (Platform.isIOS) {
      // Use method channel for iOS
      try {
        final result = await _channel.invokeMethod('initWithEntropy', {
          'entropy': entropy,
          'network': network,
        });
        return result.toString();
      } catch (e) {
        throw Exception('Failed to initialize wallet on iOS: $e');
      }
    } else {
      // Use direct FFI for Android and other platforms
      if (!isLibraryLoaded()) {
        throw Exception('DLC wallet library is not loaded. Please ensure the native library is properly installed.');
      }
      
      _loadLibrary();

      final entropyPtr = entropy.toNativeUtf8();
      final networkPtr = network.toNativeUtf8();

      try {
        final result = _initWithEntropy(entropyPtr, networkPtr);
        return _convertCStringAndFree(result);
      } finally {
        malloc.free(entropyPtr);
        malloc.free(networkPtr);
      }
    }
  }

  /// Initialize wallet from encrypted file
  /// Used for: Loading existing wallets
  // static Future<String> initFromFile(String path, String password) async {
  //   _loadLibrary();

  //   final pathPtr = path.toNativeUtf8();
  //   final passwordPtr = password.toNativeUtf8();

  //   try {
  //     final result = _initFromFile(pathPtr, passwordPtr);
  //     return _convertCStringAndFree(result);
  //   } finally {
  //     malloc.free(pathPtr);
  //     malloc.free(passwordPtr);
  //   }
  // }

  /// Get extended public key
  /// Used for: Wallet identification, sharing public wallet info
  static Future<String> getXpub() async {
    _loadLibrary();
    final result = _getXpub();
    return _convertCStringAndFree(result);
  }

  /// Get public key for child index
  /// Used for: Address generation, verification
  static Future<String> getPublicKey(int index) async {
    _loadLibrary();
    final result = _getPublicKey(0, index);
    return _convertCStringAndFree(result);
  }

  /// Get address for child index
  /// Used for: Receiving Bitcoin payments
  static Future<String> getAddress(int index) async {
    _loadLibrary();
    final result = _getAddress(0, index);
    return _convertCStringAndFree(result);
  }

  // ==================== SIGNING OPERATIONS ====================

  /// Sign hash with ECDSA
  /// Used for: Transaction signing, message authentication
  static Future<String> signHashEcdsa(
      String hash, int signerIndex, int signerIndex4, String signerPubkey) async {
    if (Platform.isIOS) {
      // Use method channel for iOS
      try {
        final result = await _channel.invokeMethod('signHashEcdsa', {
          'hash': hash,
          'signerIndex': signerIndex,
          'signerIndex4': signerIndex4,
          'signerPubkey': signerPubkey,
        });
        return result.toString();
      } catch (e) {
        throw Exception('Failed to sign hash on iOS: $e');
      }
    } else {
      // Use direct FFI for Android and other platforms
      if (!isLibraryLoaded()) {
        throw Exception('DLC wallet library is not loaded. Please ensure the native library is properly installed.');
      }
      
      _loadLibrary();

      final hashPtr = hash.toNativeUtf8();
      final signerPubkeyPtr = signerPubkey.toNativeUtf8();

      try {
        final result = _signHashEcdsa(hashPtr, 0, signerIndex, signerPubkeyPtr);

        return _convertCStringAndFree(result);
      } finally {
        malloc.free(hashPtr);
        malloc.free(signerPubkeyPtr);
      }
    }
  }

  /// Create deterministic nonce
  /// Used for: DLC protocols, ensuring nonce uniqueness
  static Future<Map<String, String>> createDeterministicNonce(
      String eventId, int index) async {
    _loadLibrary();

    final eventIdPtr = eventId.toNativeUtf8();

    try {
      final result = _createDeterministicNonce(eventIdPtr, index);
      final resultStr = _convertCStringAndFree(result);

      // Parse "secret_key public_key" format
      final parts = resultStr.split(' ');
      if (parts.length != 2) {
        throw Exception('Invalid nonce format: $resultStr');
      }

      return {
        'secret': parts[0],
        'public': parts[1],
      };
    } finally {
      malloc.free(eventIdPtr);
    }
  }

  // ==================== DLC OPERATIONS ====================

  /// Create CET adaptor signatures
  /// Used for: DLC contract creation, conditional payments
  static Future<List<String>> createCetAdaptorSigs({
    required int numDigits,
    required int numCets,
    required String digitStringTemplate,
    required String oraclePublicKey,
    required int signingKeyIndex,
    required int signingKeyIndex4,
    required String signingPublicKey,
    required List<String> nonces,
    required List<String> intervalWildcards,
    required List<String> sighashes,
  }) async {
    if (Platform.isIOS) {
      // Use method channel for iOS
      try {
        final result = await _channel.invokeMethod('createCetAdaptorSigs', {
          'numDigits': numDigits,
          'numCets': numCets,
          'digitStringTemplate': digitStringTemplate,
          'oraclePublicKey': oraclePublicKey,
          'signingKeyIndex': signingKeyIndex,
          'signingKeyIndex4': signingKeyIndex4,
          'signingPublicKey': signingPublicKey,
          'nonces': nonces,
          'intervalWildcards': intervalWildcards,
          'sighashes': sighashes,
        });
        
        // Convert the result to List<String>
        if (result is List) {
          return result.map((e) => e.toString()).toList();
        } else if (result is String) {
          return result.split(' ').where((s) => s.isNotEmpty).toList();
        } else {
          throw Exception('Unexpected result type from iOS: ${result.runtimeType}');
        }
      } catch (e) {
        throw Exception('Failed to create CET adaptor signatures on iOS: $e');
      }
    } else {
      // Use direct FFI for Android and other platforms
      if (!isLibraryLoaded()) {
        throw Exception('DLC wallet library is not loaded. Please ensure the native library is properly installed.');
      }
      
      _loadLibrary();

      final digitStringTemplatePtr = digitStringTemplate.toNativeUtf8();
      final oraclePublicKeyPtr = oraclePublicKey.toNativeUtf8();
      final signingPublicKeyPtr = signingPublicKey.toNativeUtf8();
      final noncesPtr = nonces.join(' ').toNativeUtf8();
      final intervalWildcardsPtr = intervalWildcards.join(' ').toNativeUtf8();
      final sighashesPtr = sighashes.join(' ').toNativeUtf8();

      try {
        final result = _createCetAdaptorSigs(
          numDigits,
          numCets,
          digitStringTemplatePtr,
          oraclePublicKeyPtr,
          signingKeyIndex4,
          signingKeyIndex,
          signingPublicKeyPtr,
          noncesPtr,
          intervalWildcardsPtr,
          sighashesPtr,
        );

        final resultStr = _convertCStringAndFree(result);
        return resultStr.trim().split(' ').where((s) => s.isNotEmpty).toList();
      } finally {
        malloc.free(digitStringTemplatePtr);
        malloc.free(oraclePublicKeyPtr);
        malloc.free(signingPublicKeyPtr);
        malloc.free(noncesPtr);
        malloc.free(intervalWildcardsPtr);
        malloc.free(sighashesPtr);
      }
    }
  }

  // ==================== UTILITY FUNCTIONS ====================

  /// Generate multiple addresses for a wallet
  /// Used for: Address management, HD wallet operations
  static Future<List<Map<String, String>>> generateAddresses(int count,
      {int startIndex = 0}) async {
    final addresses = <Map<String, String>>[];

    for (int i = startIndex; i < startIndex + count; i++) {
      final address = await getAddress(i);
      final publicKey = await getPublicKey(i);

      addresses.add({
        'index': i.toString(),
        'address': address,
        'publicKey': publicKey,
      });
    }

    return addresses;
  }

  // /// Create a complete DLC setup
  // /// Used for: Setting up DLC contracts with all required components
  // static Future<Map<String, dynamic>> createDlcSetup({
  //   required String eventId,
  //   required int keyIndex,
  //   required String digitStringTemplate,
  //   required String oraclePublicKey,
  //   required List<String> intervalWildcards,
  //   required List<String> sighashes,
  //   required int numDigits,
  // }) async {
  //   // Create deterministic nonce
  //   final nonce = await createDeterministicNonce(eventId, keyIndex);

  //   // Get signing public key
  //   final signingPublicKey = await getPublicKey(keyIndex);

  //   // Create multiple nonces for multi-digit outcomes
  //   final nonces = <String>[];
  //   for (int i = 0; i < numDigits; i++) {
  //     final n = await createDeterministicNonce('$eventId-$i', keyIndex);
  //     nonces.add(n['public']!);
  //   }

  //   // Create CET adaptor signatures
  //   final signatures = await createCetAdaptorSigs(
  //     numDigits: numDigits,
  //     numCets: intervalWildcards.length,
  //     digitStringTemplate: digitStringTemplate,
  //     oraclePublicKey: oraclePublicKey,
  //     signingKeyIndex: keyIndex,
  //     signingPublicKey: signingPublicKey,
  //     nonces: nonces,
  //     intervalWildcards: intervalWildcards,
  //     sighashes: sighashes,
  //   );

  //   return {
  //     'eventId': eventId,
  //     'keyIndex': keyIndex,
  //     'signingPublicKey': signingPublicKey,
  //     'nonce': nonce,
  //     'nonces': nonces,
  //     'signatures': signatures,
  //     'setup': {
  //       'digitStringTemplate': digitStringTemplate,
  //       'oraclePublicKey': oraclePublicKey,
  //       'intervalWildcards': intervalWildcards,
  //       'sighashes': sighashes,
  //     }
  //   };
  // }

  /// Sign a Bitcoin transaction hash
  /// Used for: Transaction signing in wallet applications
  static Future<String> signTransaction(String txHash, int keyIndex, int keyIndex4) async {
    final publicKey = await getPublicKey(keyIndex);
    return await signHashEcdsa(txHash, keyIndex, keyIndex4, publicKey);
  }

  /// Check if the native library is loaded
  /// Used for: Ensuring library is properly loaded before use
  static bool isLibraryLoaded() {
    if (Platform.isIOS) {
      // For iOS, we use method channels, so we consider it always "loaded"
      return true;
    } else {
      try {
        _loadLibrary();
        return _lib != null;
      } catch (e) {
        return false;
      }
    }
  }

  /// Validate wallet setup
  /// Used for: Ensuring wallet is properly initialized
  static Future<bool> isWalletInitialized() async {
    try {
      if (!isLibraryLoaded()) {
        return false;
      }
      await getXpub();
      return true;
    } catch (e) {
      return false;
    }
  }
}
