#import "DlcWalletPlugin.h"
#import "dlc_wallet_bridge.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation DlcWalletPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"dlc_wallet"
      binaryMessenger:[registrar messenger]];
  DlcWalletPlugin* instance = [[DlcWalletPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
  } else if ([@"signHashEcdsa" isEqualToString:call.method]) {
    [self handleSignHashEcdsa:call result:result];
  } else if ([@"createCetAdaptorSigs" isEqualToString:call.method]) {
    [self handleCreateCetAdaptorSigs:call result:result];
  } else if ([@"initWithEntropy" isEqualToString:call.method]) {
    [self handleInitWithEntropy:call result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)handleSignHashEcdsa:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSDictionary *args = call.arguments;
  NSString *hash = args[@"hash"];
  NSNumber *signerIndex = args[@"signerIndex"];
  NSString *signerPubkey = args[@"signerPubkey"];
  
  if (!hash || !signerIndex || !signerPubkey) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                              message:@"Missing required parameters"
                              details:nil]);
    return;
  }
  
  NSLog(@"iOS: Signing hash: %@ with index: %@, pubkey: %@", hash, signerIndex, signerPubkey);
  
  // Use the native Rust library
  const char *hashCStr = [hash UTF8String];
  const char *signerPubkeyCStr = [signerPubkey UTF8String];
  uint32_t signerIndexU32 = [signerIndex unsignedIntValue];
  
  char *signatureCStr = sign_hash_ecdsa_c(hashCStr, 0, signerIndexU32, signerPubkeyCStr);
  
  if (signatureCStr == NULL) {
    result([FlutterError errorWithCode:@"SIGNATURE_ERROR"
                              message:@"Failed to sign hash with native library"
                              details:nil]);
    return;
  }
  
  NSString *signature = [NSString stringWithUTF8String:signatureCStr];
  free_cstring(signatureCStr);
  
  NSLog(@"iOS: Generated signature: %@", signature);
  result(signature);
}

- (void)handleCreateCetAdaptorSigs:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSDictionary *args = call.arguments;
  NSNumber *numDigits = args[@"numDigits"];
  NSNumber *numCets = args[@"numCets"];
  NSString *digitStringTemplate = args[@"digitStringTemplate"];
  NSString *oraclePublicKey = args[@"oraclePublicKey"];
  NSNumber *signingKeyIndex = args[@"signingKeyIndex"];
  NSString *signingPublicKey = args[@"signingPublicKey"];
  NSArray *nonces = args[@"nonces"];
  NSArray *intervalWildcards = args[@"intervalWildcards"];
  NSArray *sighashes = args[@"sighashes"];
  
  if (!numDigits || !numCets || !digitStringTemplate || !oraclePublicKey || 
      !signingKeyIndex || !signingPublicKey || !nonces || !intervalWildcards || !sighashes) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                              message:@"Missing required parameters"
                              details:nil]);
    return;
  }
  
  // For now, return mock CET adaptor signatures for iOS
  // TODO: Replace with actual Rust FFI calls after building the library
  NSLog(@"iOS: Creating CET adaptor signatures - digits: %@, cets: %@, template: %@", 
        numDigits, numCets, digitStringTemplate);
  NSLog(@"iOS: CET Parameters:");
  NSLog(@"  numDigits: %@, numCets: %@", numDigits, numCets);
  NSLog(@"  digitStringTemplate: %@", digitStringTemplate);
  NSLog(@"  oraclePublicKey: %@", oraclePublicKey);
  NSLog(@"  signingKeyIndex: %@, signingPublicKey: %@", signingKeyIndex, signingPublicKey);
  NSLog(@"  nonces: %@", nonces);
  NSLog(@"  intervalWildcards: %@", intervalWildcards);
  NSLog(@"  sighashes: %@", sighashes);
  
  // Use the native Rust library
  const char *digitStringTemplateCStr = [digitStringTemplate UTF8String];
  const char *oraclePublicKeyCStr = [oraclePublicKey UTF8String];
  const char *signingPublicKeyCStr = [signingPublicKey UTF8String];
  const char *noncesCStr = [[nonces componentsJoinedByString:@" "] UTF8String];
  const char *intervalWildcardsCStr = [[intervalWildcards componentsJoinedByString:@" "] UTF8String];
  const char *sighashesCStr = [[sighashes componentsJoinedByString:@" "] UTF8String];
  
  uint8_t numDigitsU8 = [numDigits unsignedCharValue];
  uint32_t numCetsU32 = [numCets unsignedIntValue];
  uint32_t signingKeyIndexU32 = [signingKeyIndex unsignedIntValue];
  
  char *signaturesCStr = create_cet_adaptor_sigs_c(
    numDigitsU8, numCetsU32, digitStringTemplateCStr, oraclePublicKeyCStr,
    0, signingKeyIndexU32, signingPublicKeyCStr, noncesCStr, intervalWildcardsCStr, sighashesCStr
  );
  
  if (signaturesCStr == NULL) {
    result([FlutterError errorWithCode:@"SIGNATURE_ERROR"
                              message:@"Failed to create CET adaptor signatures with native library"
                              details:nil]);
    return;
  }
  
  NSString *signaturesStr = [NSString stringWithUTF8String:signaturesCStr];
  free_cstring(signaturesCStr);
  
  NSLog(@"iOS: Raw signatures string: %@", signaturesStr);
  
  // Parse the space-separated signatures
  NSArray *signatures = [signaturesStr componentsSeparatedByString:@" "];
  
  NSLog(@"iOS: Parsed %lu signatures", (unsigned long)signatures.count);
  
  result(signatures);
}

- (void)handleInitWithEntropy:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSDictionary *args = call.arguments;
  NSString *entropy = args[@"entropy"];
  NSString *network = args[@"network"];
  
  if (!entropy || !network) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                              message:@"Missing entropy or network parameter"
                              details:nil]);
    return;
  }
  
  // Use the native Rust library
  const char *entropyCStr = [entropy UTF8String];
  const char *networkCStr = [network UTF8String];
  
  char *xpubCStr = init_with_entropy_c(entropyCStr, networkCStr);
  
  if (xpubCStr == NULL) {
    result([FlutterError errorWithCode:@"INIT_ERROR"
                              message:@"Failed to initialize with native library"
                              details:nil]);
    return;
  }
  
  NSString *xpub = [NSString stringWithUTF8String:xpubCStr];
  free_cstring(xpubCStr);
  
  NSLog(@"iOS: Generated XPUB: %@", xpub);
  result(xpub);
}

@end
