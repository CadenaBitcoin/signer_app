# Test the dlcplazacryptlib library through its C-style interface
# Test the methods used by the app

import os
import sys
from ctypes import cdll, c_char_p, c_uint32, c_uint8

class RustInterface:
    def __init__(self):
        try:
            if hasattr(sys, 'getandroidapilevel'):
                # Running on Android
                self.lib = cdll.LoadLibrary("libdlcplazacryptlib.so")
            else:
                # Local dev environment
                dev_path = "./_dlc_plaza_oracle/dlcplazacryptlib/target/debug/libdlcplazacryptlib.so"
                if os.path.exists(dev_path):
                    self.lib = cdll.LoadLibrary(os.path.abspath(dev_path))
                else:
                    self.lib = cdll.LoadLibrary("libdlcplazacryptlib.so")
        except OSError as e:
            raise RuntimeError(f"Could not load Rust shared library: {e}")

        # Define Rust method signatures
        self.lib.init_with_entropy_c.argtypes = [c_char_p, c_char_p]
        self.lib.init_with_entropy_c.restype = c_char_p
        self.lib.get_public_key_c.argtypes = [c_uint32, c_uint32]
        self.lib.get_public_key_c.restype = c_char_p
        self.lib.sign_hash_ecdsa_c.argtypes = [c_char_p, c_uint32, c_uint32, c_char_p]
        self.lib.sign_hash_ecdsa_c.restype = c_char_p
        self.lib.create_cet_adaptor_sigs_c.argtypes = [c_uint8, c_uint32, c_char_p, c_char_p, c_uint32, c_uint32, c_char_p, c_char_p, c_char_p, c_char_p]
        self.lib.create_cet_adaptor_sigs_c.restype = c_char_p
        self.lib.create_deterministic_nonce_c.argtypes = [c_char_p, c_char_p]
        self.lib.create_deterministic_nonce_c.restype = c_char_p

    # Initialize the library, provide the secret as parameter. Return the XPUB.
    def init_with_entropy(self, entropy, network):
        # Call the Rust function (init_with_entropy_c) from the .so library
        return self.lib.init_with_entropy_c(entropy.encode('utf-8'), network.encode('utf-8')).decode("utf-8")

    # Sign a hash with a child private key (specified by index).
    def sign_hash_ecdsa(self, hash, signer_index4, signer_index5 , signer_pubkey):
        # Call the Rust function (sign_hash_ecdsa_c) from the .so library
        return self.lib.sign_hash_ecdsa_c(hash.encode('utf-8'), signer_index4, signer_index5, signer_pubkey.encode('utf-8')).decode('utf-8')

    # Create adaptor signatures for a number of CETs
    def create_cet_adaptor_sigs(self, num_digits: int, num_cets: int, digit_string_template: str, oracle_pubkey: str, signing_key_index4: int, signing_key_index5: int, signing_pubkey: str, nonces: str, interval_wildcards: str, sighashes: str):
        # Call the Rust function (create_cet_adaptor_sigs_c) from the .so library
        return self.lib.create_cet_adaptor_sigs_c(num_digits, num_cets, digit_string_template.encode('utf-8'), oracle_pubkey.encode('utf-8'), signing_key_index4, signing_key_index5, signing_pubkey.encode('utf-8'), nonces.encode('utf-8'), interval_wildcards.encode('utf-8'), sighashes.encode('utf-8')).decode('utf-8')

    # Return a child public key.
    def get_public_key(self, index4, index5):
        # Call the Rust function (get_public_key_c) from the .so library
        return self.lib.get_public_key_c(index4, index5).decode("utf-8")

    def create_deterministic_nonce(self, event_id, index):
        # Call the Rust function (create_deterministic_nonce_c) from the .so library
        return self.lib.create_deterministic_nonce_c(event_id.encode('utf-8'), str(index).encode('utf-8')).decode("utf-8")


rust_interface = None
try:
    rust_interface = RustInterface()
except OSError:
    print("ELHASALTUNK")

entropy_hex = "99d33a674ce99d33a674ce99d33a674c" # oil x 12
network = "signet"

xpub = rust_interface.init_with_entropy(entropy_hex, network)
print("xpub:", xpub)
assert(xpub == "tpubDCRo9GmRAvEWANJ5iSfMEqPoq3uYvjBPAAjrDj5iQMxAq7DCs5orw7m9xJes8hWYAwKuH3T63WrKfzzw7g9ucbjq4LUu5cgCLUPMN7gUkrL")

pubkey0 = rust_interface.get_public_key(0)
print("pubkey 0:", pubkey0)
assert(pubkey0 == "0292892b831077bc87f7767215ab631ff56d881986119ff03f1b64362e9abc70cd")

hash = "0001020300000000000000000000000000000000000000000000000000010203"
sig = rust_interface.sign_hash_ecdsa(hash, 0, pubkey0)
print("sig:", sig)


digit_string_template = "Outcome:btcusd1747220520:{digit_index}:{digit_outcome}"
oracle_pubkey = "0292892b831077bc87f7767215ab631ff56d881986119ff03f1b64362e9abc70cd"
nonces = "03bf8272fd77ac83400e8b7f1af5899ab96ce81871ca26d31fa3b80db08bdc412e 03ec14b379b5db0c5305a452ee04d4b82b5a1db90f8eddc55f1f94d5947b341ed4 0325642feb3db37b3ffa88b0754d59ad1c3116e035ee9e5557e107fd3d914fb3fb 02d597f9bd84cb925ade7efa04edf46c33a7d96cc4252647204a6961a34838d00d 03d11c778b1c4f1f7710a4b17816f02d049325220b2fb8007efd84248f08fd75dc 038fb0dbd6eb0e970c75c28ca02b614523fe59b5da000f815fcfbfcf4a4ecdd192 023f0eadc3b9c3337d31e38a9238a3c59505cc8004fa7ca6facdd3c853d824ca0d"
interval_wildcards = "0000*** 0001*** 0002***"
sighashes = "0001020300000000000000000000000000000000000000000000000000010200 0001020300000000000000000000000000000000000000000000000000010201 0001020300000000000000000000000000000000000000000000000000010202"
sigs = rust_interface.create_cet_adaptor_sigs(7, 3, digit_string_template, oracle_pubkey, 0, 0, pubkey0, nonces, interval_wildcards, sighashes)
print("signatures:", sigs)


det_nonce0 = rust_interface.create_deterministic_nonce("event001", 0)
print("nonce:", det_nonce0)
