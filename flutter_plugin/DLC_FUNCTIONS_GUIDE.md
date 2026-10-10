# DLC Functions Guide for Flutter Integration

## 📋 **Complete Function Reference**

### **1. Wallet Management Functions**

#### `init_with_entropy_c(entropy, network)`
- **Purpose**: Initialize wallet with entropy (seed)
- **Parameters**: 
  - `entropy`: Hex string (32 bytes)
  - `network`: "bitcoin" or "signet"
- **Returns**: Extended public key (XPUB)
- **Flutter Usage**:
```dart
final xpub = await DlcWallet.initWithEntropy(
  "99d33a674ce99d33a674ce99d33a674c",
  "signet"
);
```

#### `init_from_file_c(path, password)`
- **Purpose**: Load wallet from encrypted file
- **Parameters**:
  - `path`: File path to encrypted wallet
  - `password`: Decryption password
- **Returns**: Extended public key (XPUB)
- **Flutter Usage**:
```dart
final xpub = await DlcWallet.initFromFile(
  "/path/to/wallet.enc",
  "mypassword"
);
```

#### `get_xpub_c()`
- **Purpose**: Get wallet's extended public key
- **Returns**: XPUB string
- **Flutter Usage**:
```dart
final xpub = await DlcWallet.getXpub();
```

#### `get_public_key_c(index)`
- **Purpose**: Get child public key at index
- **Parameters**: `index`: Child key index (0, 1, 2, ...)
- **Returns**: Public key hex string
- **Flutter Usage**:
```dart
final pubkey = await DlcWallet.getPublicKey(0);
```

#### `get_address_c(index)`
- **Purpose**: Get Bitcoin address at index
- **Parameters**: `index`: Address index
- **Returns**: Bitcoin address string
- **Flutter Usage**:
```dart
final address = await DlcWallet.getAddress(0);
```

### **2. Signing Operations**

#### `sign_hash_ecdsa_c(hash, signerIndex, signerPubkey)`
- **Purpose**: Sign hash with ECDSA
- **Parameters**:
  - `hash`: 32-byte hash (hex)
  - `signerIndex`: Key index for signing
  - `signerPubkey`: Signer's public key
- **Returns**: ECDSA signature
- **Flutter Usage**:
```dart
final signature = await DlcWallet.signHashEcdsa(
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  0, 0,
  pubkey
);
```

#### `create_deterministic_nonce_c(eventId, index)`
- **Purpose**: Create deterministic nonce for DLC
- **Parameters**:
  - `eventId`: Unique event identifier
  - `index`: Key index
- **Returns**: Nonce secret and public key
- **Flutter Usage**:
```dart
final nonce = await DlcWallet.createDeterministicNonce(
  "btc_price_2024",
  0
);
// Returns: {'secret': '...', 'public': '...'}
```

### **3. DLC-Specific Operations**

#### `create_cet_adaptor_sigs_c(...)`
- **Purpose**: Create Contract Execution Transaction adaptor signatures
- **Parameters**:
  - `numDigits`: Number of oracle outcome digits
  - `numCets`: Number of CETs
  - `digitStringTemplate`: Template for outcomes
  - `oraclePublicKey`: Oracle's public key
  - `signingKeyIndex`: Index of signing key
  - `signingPublicKey`: Signer's public key
  - `nonces`: Oracle nonces (space-separated)
  - `intervalWildcards`: Outcome intervals
  - `sighashes`: Transaction hashes to sign
- **Returns**: List of adaptor signatures
- **Flutter Usage**:
```dart
final signatures = await DlcWallet.createCetAdaptorSigs(
  numDigits: 2,
  numCets: 3,
  digitStringTemplate: 'BTCUSD',
  oraclePublicKey: '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
  signingKeyIndex: 0,
  signingKeyIndex4: 0,
  signingPublicKey: await DlcWallet.getPublicKey(0),
  nonces: ['nonce1', 'nonce2'],
  intervalWildcards: ['50000-60000', '60000-70000'],
  sighashes: ['hash1', 'hash2']
);
```

### **4. Utility Functions (Python/Internal)**

#### `combine_pubkeys(keys_hex)`
- **Purpose**: Combine multiple public keys
- **Parameters**: Space-separated public keys
- **Returns**: Combined public key

#### `combine_seckeys(keys_hex)`
- **Purpose**: Combine multiple secret keys
- **Parameters**: Space-separated secret keys
- **Returns**: Combined secret key

#### `verify_cet_adaptor_sigs(...)`
- **Purpose**: Verify CET adaptor signatures
- **Returns**: Boolean verification result

#### `create_final_cet_sig(...)`
- **Purpose**: Create final CET signature when oracle reveals outcome
- **Returns**: Final signature for settlement

#### `create_final_cet_sigs(...)`
- **Purpose**: Create both final signatures for DLC settlement
- **Returns**: Both party signatures

## 🚀 **Flutter Integration Patterns**

### **1. Basic Wallet Setup**
```dart
// Initialize wallet
final xpub = await DlcWallet.initWithEntropy(entropy, "signet");

// Generate addresses
final addresses = await DlcWallet.generateAddresses(10);

// Sign transaction
final signature = await DlcWallet.signTransaction(txHash, keyIndex, keyIndex4);
```

### **2. DLC Contract Creation**
```dart
// Create complete DLC setup
final dlcSetup = await DlcWallet.createDlcSetup(
  eventId: 'btc_price_2024',
  keyIndex: 0,
  digitStringTemplate: 'BTCUSD',
  oraclePublicKey: oracleKey,
  intervalWildcards: outcomes,
  sighashes: transactionHashes,
  numDigits: 2,
);

// Access components
final eventId = dlcSetup['eventId'];
final signatures = dlcSetup['signatures'];
final nonces = dlcSetup['nonces'];
```

### **3. Transaction Signing**
```dart
// Sign Bitcoin transaction
final txSignature = await DlcWallet.signTransaction(
  transactionHash,
  keyIndex, keyIndex4,
);

// Sign arbitrary hash
final hashSignature = await DlcWallet.signHashEcdsa(
  messageHash,
  keyIndex, keyIndex4,
  publicKey
);
```

## 📱 **Real-World Use Cases**

### **1. Bitcoin Wallet App**
- **Wallet Creation**: `initWithEntropy()` for new wallets
- **Address Generation**: `generateAddresses()` for receiving funds
- **Transaction Signing**: `signTransaction()` for sending Bitcoin
- **Backup/Restore**: `initFromFile()` for wallet recovery

### **2. DLC Trading Platform**
- **Contract Setup**: `createDlcSetup()` for new contracts
- **Signature Creation**: `createCetAdaptorSigs()` for contract execution
- **Oracle Integration**: `createDeterministicNonce()` for oracle coordination
- **Settlement**: Final signature functions for contract closure

### **3. Multi-Signature Wallet**
- **Key Combination**: `combine_pubkeys()` for multi-sig addresses
- **Coordinated Signing**: Multiple `signHashEcdsa()` calls
- **Verification**: Public key verification functions

## 🔧 **Build & Integration Steps**

### **1. Build Rust Library**
```bash
# Run the build script
./build_for_flutter.sh

# Or manually for Android
cargo ndk -t arm64-v8a -o flutter_plugin/android/src/main/jniLibs build --release
```

### **2. Flutter Plugin Setup**
```bash
cd flutter_plugin/example
flutter pub get
flutter run
```

### **3. Platform-Specific Files**
- **Android**: `libdlcplazacryptlib.so` in `jniLibs/`
- **iOS**: `libdlcplazacryptlib.a` in iOS framework
- **Desktop**: `.so/.dylib/.dll` files in platform directories

## 🎯 **Function Categories & Usage Priority**

### **High Priority (Essential for Bitcoin Wallet)**
1. `initWithEntropy()` - Wallet creation
2. `getAddress()` - Receiving payments
3. `signTransaction()` - Sending payments
4. `getXpub()` - Wallet identification

### **Medium Priority (Advanced Features)**
1. `createDeterministicNonce()` - DLC protocols
2. `signHashEcdsa()` - Custom signing
3. `generateAddresses()` - Address management

### **Low Priority (Specialized DLC)**
1. `createCetAdaptorSigs()` - DLC contracts
2. `createDlcSetup()` - Full DLC workflow
3. Verification functions - Contract validation

## 📊 **Performance Considerations**

- **FFI Overhead**: Minimal for single calls
- **Memory Management**: Automatic cleanup with `free_cstring`
- **Parallel Operations**: Use `Future.wait()` for multiple addresses
- **Error Handling**: All functions return proper error messages

## 🔐 **Security Best Practices**

1. **Entropy Generation**: Use secure random for wallet creation
2. **Key Storage**: Never expose private keys in Flutter
3. **Network Selection**: Use appropriate network (mainnet/testnet)
4. **Input Validation**: Validate all hex strings and indices
5. **Error Handling**: Proper exception handling for all operations

This comprehensive guide covers all available DLC functions and their practical usage in Flutter applications for Bitcoin wallet and DLC operations. 