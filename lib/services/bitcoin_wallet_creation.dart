import 'dart:convert';
import 'dart:typed_data';
import 'package:bech32/bech32.dart';
import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:bip32/bip32.dart';
import 'package:bs58check/bs58check.dart' as Base58CheckCodec;
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:bs58check/bs58check.dart';
import 'package:get/get.dart';
import 'package:hex/hex.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:signer/services/bitcoin_wallet_creation.dart';
import 'package:signer/src/ui/controllers/appController.dart';

import 'bitcoin_wallet_creation.dart';

class BitcoinWallet {
  final String path; // the derivation path used
  final String privateKey; // hex
  final String publicKey; // hex (compressed)
  final String address; // base58 P2PKH

  BitcoinWallet({required this.path, required this.privateKey, required this.publicKey, required this.address});
}

// Future<BitcoinWallet> generateBitcoinWalletTestnet({required String mnemonic, String derivationPath = "m/84'/1'/0'/0/0"}) async {
//   // 1. Validate mnemonic
//   if (!bip39.validateMnemonic(mnemonic)) {
//     throw ArgumentError("Invalid mnemonic");
//   }
//
//   // 2. Convert mnemonic to seed
//   final seed = bip39.mnemonicToSeed(mnemonic);
//
//   // 3. Create BIP32 root node for testnet
//   // final testnet = bip32.NetworkType(
//   //   bip32: bip32.Bip32Type(
//   //     public: 0x043587cf, // tpub
//   //     private: 0x04358394, // testnet private
//   //   ),
//   //   wif: 0xEF, // testnet WIF prefix
//   // );
//   final signet = bip32.NetworkType(
//     bip32: bip32.Bip32Type(
//       public: 0x043587cf, // tpub (same as testnet)
//       private: 0x04358394, // tprv (same as testnet)
//     ),
//     wif: 0xEF, // same as testnet
//   );
//
//   final root = BIP32.fromSeed(seed, signet);
//
//   // 4. Derive path
//   final child = root.derivePath(derivationPath);
//
//   // 5. Keys
//   final privKeyBytes = child.privateKey!;
//   final pubKeyBytes = child.publicKey;
//
//   final privateKeyHex = hex.encode(privKeyBytes);
//   final publicKeyHex = hex.encode(pubKeyBytes);
//
//   // 6. Generate Testnet P2PKH address: Base58Check(0x6F + RIPEMD160(SHA256(pubKey)))
//   final sha256Hash = sha256.convert(pubKeyBytes).bytes;
//   final ripemd160Hash = RIPEMD160Digest().process(Uint8List.fromList(sha256Hash));
//   final payload = <int>[0x6F, ...ripemd160Hash]; // 0x6F = testnet
//   final address = Base58CheckCodec.encode(Uint8List.fromList(payload));
//
//   print("== Testnet Address: $address");
//
//   return BitcoinWallet(path: derivationPath, privateKey: privateKeyHex, publicKey: publicKeyHex, address: address);
// }

Future<BitcoinWallet> generateBitcoinWalletTestnet({required String mnemonic, String derivationPath = "m/84'/1'/0'/0/0"}) async {
  final appController = Get.find<AppController>();
  if (!bip39.validateMnemonic(mnemonic)) {
    throw ArgumentError("Invalid mnemonic");
  }

  final seed = bip39.mnemonicToSeed(mnemonic);

  final testnet = NetworkType(bip32: Bip32Type(public: 0x043587cf, private: 0x04358394), wif: 0xEF);

  final root = BIP32.fromSeed(seed, testnet);
  final child = root.derivePath(derivationPath);

  final privKey = child.privateKey!;
  final pubKey = child.publicKey;

  // 👇 Replace manual logic with helper function
  final address = generateP2WPKHAddress(pubKey, isTestnet: appController.isTestnet);


  return BitcoinWallet(path: derivationPath, privateKey: hex.encode(privKey), publicKey: hex.encode(pubKey), address: address);
}

List<int> convertBits(Uint8List data, int fromBits, int toBits, bool pad) {
  int acc = 0;
  int bits = 0;
  final maxv = (1 << toBits) - 1;
  final result = <int>[];

  for (final value in data) {
    if (value < 0 || (value >> fromBits) != 0) {
      throw ArgumentError("Invalid input value: $value");
    }

    acc = (acc << fromBits) | value;
    bits += fromBits;

    while (bits >= toBits) {
      bits -= toBits;
      result.add((acc >> bits) & maxv);
    }
  }

  if (pad) {
    if (bits > 0) {
      result.add((acc << (toBits - bits)) & maxv);
    }
  } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
    throw ArgumentError("Could not convert bits without padding");
  }

  return result;
}

String generateP2WPKHAddress(Uint8List pubKey, {bool isTestnet = true}) {
  // 1. HASH160 (RIPEMD160(SHA256(pubkey)))
  final sha256Hash = sha256.convert(pubKey).bytes;
  final ripemd160Hash = RIPEMD160Digest().process(Uint8List.fromList(sha256Hash));

  // 2. Convert to 5-bit groups (Bech32 requirement)
  final converted = convertBits(Uint8List.fromList(ripemd160Hash), 8, 5, true);

  // 3. Add witness version 0
  final words = [0] + converted;

  // 4. Encode using bech32
  final hrp = isTestnet ? 'tb' : 'bc'; // human-readable part
  final segwit = Bech32(hrp, words);
  return bech32.encode(segwit);
}

// Future<BitcoinWallet> generateBitcoinWallet({required String mnemonic, String derivationPath = "m/44'/0'/0'/0/0"}) async {
//   // 1. Validate mnemonic
//   if (!bip39.validateMnemonic(mnemonic)) {
//     throw ArgumentError("Invalid mnemonic");
//   }
//
//   // 2. Convert mnemonic to seed (512-bit)
//   final seed = bip39.mnemonicToSeed(mnemonic);
//
//   // 3. Create BIP32 root node
//   final root = BIP32.fromSeed(seed);
//   final string = root.neutered().toBase58();
//
//   // 4. Derive the desired child using the path
//   final child = root.derivePath(derivationPath);
//
//   // 5. Extract private and public keys
//   final privKeyBytes = child.privateKey!;
//   final pubKeyBytes = child.publicKey; // compressed 33‑byte
//
//   final privateKeyHex = hex.encode(privKeyBytes);
//   final publicKeyHex = hex.encode(pubKeyBytes);
//
//   // 6. Compute P2PKH address: Base58Check(0x00 + RIPEMD160(SHA256(pubKey)))
//   final sha256Hash = sha256.convert(pubKeyBytes).bytes;
//   final ripemd160Hash = RIPEMD160Digest().process(Uint8List.fromList(sha256Hash));
//
//   ///these two lines used for mainnet
//   final payload = <int>[0x00, ...ripemd160Hash];
//   final address = Base58CheckCodec.encode(ripemd160Hash);
//   // ///these two lines used for testnet
//   // final payload = <int>[0x6F, ...ripemd160Hash]; // 0x6F = 111 in decimal, testnet version byte
//   // final address = Base58CheckCodec.encode(Uint8List.fromList(payload));
//
//   print("================+$address");
//
//   // 7. Return your wallet object
//   return BitcoinWallet(path: derivationPath, privateKey: privateKeyHex, publicKey: publicKeyHex, address: address);
// }

bool isValidBitcoinAddress(String address) {
  final base58RegExp = RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$');
  final bech32RegExp = RegExp(r'^(bc1)[0-9a-z]{39,59}$');

  return base58RegExp.hasMatch(address) || bech32RegExp.hasMatch(address);
}
