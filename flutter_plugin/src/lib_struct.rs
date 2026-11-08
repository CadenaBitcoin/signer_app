use crate::adaptor_signature::{
    create_cet_adaptor_signatures, create_final_cet_signature, create_final_cet_signatures,
    sign_hash_ecdsa_with_key, sign_schnorr_with_nonce_sec, verify_cet_adaptor_signatures,
};
use crate::hd_wallet_storage::HDWalletStorage;

use bitcoin::bip32::Xpub;
// use bitcoin::hashes::{sha256, Hash};
// use bitcoin::hex::DisplayHex;
use bitcoin::key::{Keypair, Secp256k1};
use bitcoin::secp256k1::{All, PublicKey, SecretKey};
use bitcoin::Address;
use secp256k1_zkp::schnorr::Signature as SchnorrSignature;
use secp256k1_zkp::{EcdsaAdaptorSignature, Scalar};
use std::sync::{OnceLock, RwLock};

pub(crate) struct Lib {
    hd_wallet_storage: Option<HDWalletStorage>,
    secp: Secp256k1<All>,
}

impl Lib {
    pub(crate) fn new_empty() -> Self {
        Self {
            hd_wallet_storage: None,
            secp: Secp256k1::new(),
        }
    }

    pub(crate) fn init_from_secret_file(
        &mut self,
        path_for_secret_file: &str,
        encryption_password: &str,
        allow_reinit: bool,
    ) -> Result<(), String> {
        if !allow_reinit && self.hd_wallet_storage.is_some() {
            return Err("Library already initialized!".to_string());
        }
        let hd_wallet_storage =
            HDWalletStorage::new_from_secret_file(path_for_secret_file, encryption_password)?;
        self.hd_wallet_storage = Some(hd_wallet_storage);
        Ok(())
    }

    // #[cfg(test)]
    pub(crate) fn init_with_entropy(
        &mut self,
        entropy: &Vec<u8>,
        network: &str,
    ) -> Result<(), String> {
        let hd_wallet = HDWalletStorage::new_with_entropy(entropy, network)?;
        self.hd_wallet_storage = Some(hd_wallet);
        Ok(())
    }

    /// Return the XPUB
    pub(crate) fn get_xpub(&self) -> Result<Xpub, String> {
        if let Some(hd_wallet) = &self.hd_wallet_storage {
            hd_wallet.get_xpub()
        } else {
            Err("Library not initialized!".to_string())
        }
    }

    fn get_child_keypair(&self, index: u32) -> Result<Keypair, String> {
        if let Some(hd_wallet) = &self.hd_wallet_storage {
            hd_wallet.get_child_keypair(index)
        } else {
            Err("Library not initialized!".to_string())
        }
    }

    /// Return a child public key
    pub(crate) fn get_child_public_key(&self, index: u32) -> Result<PublicKey, String> {
        if let Some(hd_wallet) = &self.hd_wallet_storage {
            hd_wallet.get_child_public_key(index)
        } else {
            Err("Library not initialized!".to_string())
        }
    }

    /// Return a child address
    pub(crate) fn get_address(&self, index: u32) -> Result<Address, String> {
        if let Some(hd_wallet) = &self.hd_wallet_storage {
            hd_wallet.get_address(index)
        } else {
            Err("Library not initialized!".to_string())
        }
    }

    fn verify_child_public_key_intern(
        &self,
        index: u32,
        pubkey: &PublicKey,
        print_entity: &str,
    ) -> Result<bool, String> {
        if let Some(hd_wallet) = &self.hd_wallet_storage {
            hd_wallet.verify_child_public_key_intern(index, pubkey, print_entity)
        } else {
            Err("Library not initialized!".to_string())
        }
    }

    /// Verify a child public key
    pub(crate) fn verify_child_public_key(
        &self,
        index: u32,
        pubkey: &PublicKey,
    ) -> Result<bool, String> {
        self.verify_child_public_key_intern(index, pubkey, "Pubkey")
    }

    pub(crate) fn sign_hash_ecdsa(
        &self,
        hash: &[u8; 32],
        index: u32,
        signer_pubkey: &PublicKey,
    ) -> Result<Vec<u8>, String> {
        let keypair = self.get_child_keypair(index)?;
        // verify pubkey
        let _ = self.verify_child_public_key_intern(index, signer_pubkey, "Signer pubkey")?;

        sign_hash_ecdsa_with_key(&self.secp, hash, &keypair.secret_key())
    }

    // /// Create a nonce value deterministically
    // pub(crate) fn create_deterministic_nonce(
    //     &self,
    //     event_id: &str,
    //     index: u32,
    // ) -> Result<(String, PublicKey), String> {
    //     let msg = format!("This is a message for creating a deterministic nonce for event with ID {} and index {}", event_id, index);
    //     let hash = sha256::Hash::hash(msg.as_bytes()).to_byte_array();
    //     let secretkey = SecretKey::from_slice(&hash).map_err(|e| e.to_string())?;
    //     let publickey = secretkey.public_key(&self.secp);
    //     Ok((hash.to_lower_hex_string(), publickey))
    // }

    /// Sign a message using Schnorr, using a child key
    pub(crate) fn sign_schnorr_with_nonce(
        &self,
        msg: &str,
        nonce_sec: &[u8; 32],
        index: u32,
    ) -> Result<SchnorrSignature, String> {
        let kp = self.get_child_keypair(index)?;
        sign_schnorr_with_nonce_sec(&self.secp, &kp, msg, nonce_sec)
    }

    pub(crate) fn combine_seckeys(secrets: &Vec<SecretKey>) -> Result<SecretKey, String> {
        if secrets.len() == 0 {
            return Err("At least one key is required".to_string());
        }
        let secret = secrets[0];
        let result = secrets.iter().skip(1).fold(secret, |accum, s| {
            accum.add_tweak(&Scalar::from(*s)).unwrap()
        });
        Ok(result)
    }

    pub(crate) fn create_cet_adaptor_sigs(
        &self,
        num_digits: u8,
        num_cets: u64,
        digit_string_template: &str,
        oracle_pubkey: &PublicKey,
        signing_key_index: u32,
        signing_pubkey: &PublicKey,
        nonces: &Vec<PublicKey>,
        interval_wildcards: &Vec<String>,
        sighashes: &Vec<[u8; 32]>,
    ) -> Result<Vec<EcdsaAdaptorSignature>, String> {
        // Prepare signing key
        let sign_keypair = self.get_child_keypair(signing_key_index)?;
        // Verify signing pubkey
        let _ = self.verify_child_public_key_intern(
            signing_key_index,
            signing_pubkey,
            "Signer pubkey",
        )?;

        create_cet_adaptor_signatures(
            &self.secp,
            num_digits,
            num_cets,
            digit_string_template,
            oracle_pubkey,
            &sign_keypair,
            nonces,
            interval_wildcards,
            sighashes,
        )
    }

    pub(crate) fn verify_cet_adaptor_sigs(
        &self,
        num_digits: u8,
        num_cets: u64,
        digit_string_template: &str,
        oracle_pubkey: &PublicKey,
        signing_pubkey: &PublicKey,
        nonces: &Vec<PublicKey>,
        interval_wildcards: &Vec<String>,
        sighashes: &Vec<[u8; 32]>,
        signatures: &Vec<EcdsaAdaptorSignature>,
    ) -> Result<(), String> {
        verify_cet_adaptor_signatures(
            &self.secp,
            num_digits,
            num_cets,
            digit_string_template,
            oracle_pubkey,
            signing_pubkey,
            nonces,
            interval_wildcards,
            sighashes,
            signatures,
        )
    }

    /// Decrypt a signature on a CET when outcome signatures are available.
    /// Return the decrypted signature.
    pub fn create_final_cet_sig(
        pubkey: &PublicKey,
        num_digits: u8,
        oracle_signatures: &Vec<SchnorrSignature>,
        cet_value_wildcard: &str,
        cet_sighash: &[u8; 32],
        adaptor_signature: &EcdsaAdaptorSignature,
    ) -> Result<Vec<u8>, String> {
        create_final_cet_signature(
            pubkey,
            num_digits,
            oracle_signatures,
            cet_value_wildcard,
            cet_sighash,
            adaptor_signature,
        )
    }

    /// Create the two signatures on a CET when outcome signatures are available.
    /// Return the decrypted signature of the other, and my own signature (newly created).
    pub fn create_final_cet_sigs(
        &self,
        signing_key_index: u32,
        signing_pubkey: &PublicKey,
        other_pubkey: &PublicKey,
        num_digits: u8,
        oracle_signatures: &Vec<SchnorrSignature>,
        cet_value_wildcard: &str,
        cet_sighash: &[u8; 32],
        other_adaptor_signature: &EcdsaAdaptorSignature,
    ) -> Result<(Vec<u8>, Vec<u8>), String> {
        // Prepare signing key
        let sign_keypair = self.get_child_keypair(signing_key_index)?;
        // verify signer pubkey
        let _ = self.verify_child_public_key_intern(
            signing_key_index,
            signing_pubkey,
            "Signer pubkey",
        )?;

        create_final_cet_signatures(
            &self.secp,
            &sign_keypair,
            other_pubkey,
            num_digits,
            oracle_signatures,
            cet_value_wildcard,
            cet_sighash,
            other_adaptor_signature,
        )
    }
}

pub(crate) fn global_lib() -> &'static RwLock<Lib> {
    static GLOBAL_LIB: OnceLock<RwLock<Lib>> = OnceLock::new();
    GLOBAL_LIB.get_or_init(|| RwLock::new(Lib::new_empty()))
}
