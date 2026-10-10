#ifndef DLC_WALLET_BRIDGE_H
#define DLC_WALLET_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Function declarations for the Rust library
char* init_with_entropy_c(const char* entropy, const char* network);
char* get_public_key_c(uint32_t index4, uint32_t index5);
char* sign_hash_ecdsa_c(const char* hash, uint32_t signer_index4, uint32_t signer_index5, const char* signer_pubkey);
char* create_cet_adaptor_sigs_c(uint8_t num_digits, uint32_t num_cets, const char* digit_string_template, const char* oracle_public_key, uint32_t signing_key_index4, uint32_t signing_key_index5, const char* signing_public_key, const char* nonces, const char* interval_wildcards, const char* sighashes);
char* create_deterministic_nonce_c(const char* event_id, uint32_t index);
char* get_xpub_c(void);
char* get_address_c(uint32_t index4, uint32_t index5);
// char* init_from_file_c(const char* path, const char* password);
void free_cstring(char* s);

#ifdef __cplusplus
}
#endif

#endif /* DLC_WALLET_BRIDGE_H */


