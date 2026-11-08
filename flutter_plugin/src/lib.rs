mod adaptor_signature;
mod hd_wallet_storage;
mod lib_struct;
mod network;
mod parse;
mod secret_entropy_storage;
#[cfg(test)]
mod test_lib;

use crate::adaptor_signature::combine_pubkeys_wrapper;
use crate::lib_struct::{global_lib, Lib};
use crate::parse::{
    hash_from_hex, keypair_from_sec_key_hex, pubkey_from_hex, schnorr_sig_from_hex,
};
use crate::secret_entropy_storage::parse_entropy_hex;

use bitcoin::hex::{DisplayHex, FromHex};
use bitcoin::secp256k1::{PublicKey, SecretKey};
use secp256k1_zkp::schnorr::Signature as SchnorrSignature;
use secp256k1_zkp::EcdsaAdaptorSignature;  // Import missing types
use std::str::FromStr;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

// Conditional compilation to exclude PyO3-related code for Android
#[cfg(feature = "with-pyo3")]
use pyo3::prelude::*;
#[cfg(feature = "with-pyo3")]
use pyo3::exceptions::PyException;
#[cfg(feature = "with-pyo3")]
use pyo3::wrap_pyfunction;


/// Initialize the library, load secret from encrypted file. Return the XPUB.
fn init_intern(
    path_for_secret_file: &str,
    encryption_password: &str,
    allow_reinit: bool,
) -> Result<String, String> {
    global_lib().write().unwrap().init_from_secret_file(
        path_for_secret_file,
        encryption_password,
        allow_reinit,
    )?;
    let xpub = global_lib().read().unwrap().get_xpub()?;
    Ok(xpub.to_string())
}

/// Initialize the library, provide the secret as parameter. Return the XPUB.
// #[cfg(test)]
fn init_with_entropy_intern(entropy: &str, network: &str) -> Result<String, String> {
    let entropy_bin = parse_entropy_hex(entropy)?;
    global_lib()
        .write()
        .unwrap()
        .init_with_entropy(&entropy_bin, network)?;
    let xpub = global_lib().read().unwrap().get_xpub()?;
    Ok(xpub.to_string())
}

fn get_xpub_intern() -> Result<String, String> {
    let xpub = global_lib().read().unwrap().get_xpub()?;
    Ok(xpub.to_string())
}

fn get_public_key_intern(index: u32) -> Result<String, String> {
    let pubkey = global_lib().read().unwrap().get_child_public_key(index)?;
    Ok(pubkey.to_string())
}

fn get_address_intern(index: u32) -> Result<String, String> {
    let address = global_lib().read().unwrap().get_address(index)?;
    Ok(address.to_string())
}

fn verify_public_key_intern(index: u32, pubkey_str: &str) -> Result<bool, String> {
    let pubkey =
        pubkey_from_hex(pubkey_str).map_err(|e| format!("Failed to parse pubkey {}", e))?;
    let verify_result = global_lib()
        .read()
        .unwrap()
        .verify_child_public_key(index, &pubkey)?;
    Ok(verify_result)
}

fn sign_hash_ecdsa_intern(
    hash_str: &str,
    index: u32,
    signer_pubkey_str: &str,
) -> Result<String, String> {
    let hash = <[u8; 32]>::from_hex(hash_str)
        .map_err(|e| format!("Failed to parse hash hex, {}", e.to_string()))?;
    let signer_pubkey = pubkey_from_hex(signer_pubkey_str)
        .map_err(|e| format!("Failed to parse signer pubkey {}", e))?;
    let sig = global_lib()
        .read()
        .unwrap()
        .sign_hash_ecdsa(&hash, index, &signer_pubkey)?;
    Ok(sig.to_lower_hex_string())
}

// fn create_deterministic_nonce_intern(
//     event_id: &str,
//     index: u32,
// ) -> Result<(String, String), String> {
//     let (sk, pk) = global_lib()
//         .read()
//         .unwrap()
//         .create_deterministic_nonce(event_id, index)?;
//     Ok((sk, pk.to_string()))
// }

// Schnorr signing with nonce
fn sign_schnorr_with_nonce_intern(
    msg: &str,
    nonce_sec_hex: &str,
    index: u32,
) -> Result<String, String> {
    let nonce_sec_bin = <[u8; 32]>::from_hex(&nonce_sec_hex)
        .map_err(|e| format!("Error in nonce hex string {}", e))?;
    let sig = global_lib()
        .read()
        .unwrap()
        .sign_schnorr_with_nonce(msg, &nonce_sec_bin, index)?;
    Ok(sig.to_string())
}

pub fn combine_pubkeys_intern(keys_hex: &str) -> Result<String, String> {
    let keys_split: Vec<_> = keys_hex.split(" ").collect();
    let mut keys = Vec::<PublicKey>::with_capacity(keys_split.len());
    for i in 0..keys_split.len() {
        let key_hex = keys_split[i].trim();
        if key_hex.len() > 0 {
            let key = pubkey_from_hex(&keys_split[i])
                .map_err(|e| format!("Failed to parse element {} {}", i, e))?;
            keys.push(key);
        }
    }
    let combined_key = combine_pubkeys_wrapper(keys.iter().collect::<Vec<_>>().as_slice())?;
    Ok(combined_key.to_string())
}

pub fn combine_seckeys_intern(keys_hex: &str) -> Result<String, String> {
    let keys_split: Vec<_> = keys_hex.split(" ").collect();
    let mut keys = Vec::<SecretKey>::with_capacity(keys_split.len());
    for i in 0..keys_split.len() {
        let key_hex = keys_split[i].trim();
        if key_hex.len() > 0 {
            let keypair = keypair_from_sec_key_hex(&key_hex)
                .map_err(|e| format!("Failed to parse element {} {}", i, e))?;
            keys.push(keypair.secret_key());
        }
    }
    let combined_key = Lib::combine_seckeys(&keys)?;
    Ok(combined_key.display_secret().to_string())
}

fn create_cet_adaptor_sigs_intern(
    num_digits: u8,
    num_cets: u64,
    digit_string_template: &str,
    oracle_pubkey_str: &str,
    signing_key_index: u32,
    signing_pubkey_str: &str,
    nonces: &str,
    interval_wildcards: &str,
    sighashes: &str,
) -> Result<String, String> {
    let nonces_split: Vec<_> = nonces.split(" ").collect();
    let mut nonces = Vec::<PublicKey>::with_capacity(nonces_split.len());
    for i in 0..nonces_split.len() {
        let key_hex = nonces_split[i].trim();
        if key_hex.len() > 0 {
            let pubkey = pubkey_from_hex(&key_hex)
                .map_err(|e| format!("Failed to parse element {} {}", i, e))?;
            nonces.push(pubkey);
        }
    }
    if nonces.len() != num_digits as usize {
        return Err(format!(
            "Wrong number of nonces {} {}",
            nonces.len(),
            num_digits
        ));
    }

    let wcs_split: Vec<_> = interval_wildcards.split(" ").collect();
    let mut wcs = Vec::<String>::with_capacity(wcs_split.len());
    for i in 0..wcs_split.len() {
        let wc = wcs_split[i].trim();
        if wc.len() > 0 {
            wcs.push(wc.to_owned());
        }
    }
    if wcs.len() != num_cets as usize {
        return Err(format!(
            "Wrong number of wildcards {} {}",
            wcs.len(),
            num_cets
        ));
    }

    let shs_split: Vec<_> = sighashes.split(" ").collect();
    let mut shs = Vec::<[u8; 32]>::with_capacity(shs_split.len());
    for i in 0..shs_split.len() {
        let sh = shs_split[i].trim();
        if sh.len() > 0 {
            let hash =
                hash_from_hex(&sh).map_err(|e| format!("Failed to parse element {} {}", i, e))?;
            shs.push(hash);
        }
    }
    if shs.len() != num_cets as usize {
        return Err(format!(
            "Wrong number of sighashes {} {}",
            shs.len(),
            num_cets
        ));
    }

    let oracle_pubkey = pubkey_from_hex(oracle_pubkey_str)
        .map_err(|e| format!("Failed to parse oracle pubkey {}", e))?;
    let signing_pubkey = pubkey_from_hex(signing_pubkey_str)
        .map_err(|e| format!("Failed to parse signing pubkey {}", e))?;

    let sigs = global_lib().read().unwrap().create_cet_adaptor_sigs(
        num_digits,
        num_cets,
        digit_string_template,
        &oracle_pubkey,
        signing_key_index,
        &signing_pubkey,
        &nonces,
        &wcs,
        &shs,
    )?;

    let mut sigs_str = String::new();
    for s in sigs.iter() {
        sigs_str += &s.as_ref().to_lower_hex_string();
        sigs_str += " ";
    }

    Ok(sigs_str)
}

fn verify_cet_adaptor_sigs_intern(
    num_digits: u8,
    num_cets: u64,
    digit_string_template: &str,
    oracle_pubkey_str: &str,
    signing_pubkey_str: &str,
    nonces: &str,
    interval_wildcards: &str,
    sighashes: &str,
    signatures: &str,
) -> Result<bool, String> {
    let nonces_split: Vec<_> = nonces.split(" ").collect();
    let mut nonces = Vec::<PublicKey>::with_capacity(nonces_split.len());
    for i in 0..nonces_split.len() {
        let key_hex = nonces_split[i].trim();
        if key_hex.len() > 0 {
            let pubkey = pubkey_from_hex(&key_hex)
                .map_err(|e| format!("Failed to parse element {} {}", i, e))?;
            nonces.push(pubkey);
        }
    }
    if nonces.len() != num_digits as usize {
        return Err(format!(
            "Wrong number of nonces {} {}",
            nonces.len(),
            num_digits
        ));
    }

    let wcs_split: Vec<_> = interval_wildcards.split(" ").collect();
    let mut wcs = Vec::<String>::with_capacity(wcs_split.len());
    for i in 0..wcs_split.len() {
        let wc = wcs_split[i].trim();
        if wc.len() > 0 {
            wcs.push(wc.to_owned());
        }
    }
    if wcs.len() != num_cets as usize {
        return Err(format!(
            "Wrong number of wildcards {} {}",
            wcs.len(),
            num_cets
        ));
    }

    let shs_split: Vec<_> = sighashes.split(" ").collect();
    let mut shs = Vec::<[u8; 32]>::with_capacity(shs_split.len());
    for i in 0..shs_split.len() {
        let sh = shs_split[i].trim();
        if sh.len() > 0 {
            let hash =
                hash_from_hex(&sh).map_err(|e| format!("Failed to parse element {} {}", i, e))?;
            shs.push(hash);
        }
    }
    if shs.len() != num_cets as usize {
        return Err(format!(
            "Wrong number of sighashes {} {}",
            shs.len(),
            num_cets
        ));
    }

    let sigs_split: Vec<_> = signatures.split(" ").collect();
    let mut sigs = Vec::<EcdsaAdaptorSignature>::with_capacity(sigs_split.len());
    for i in 0..sigs_split.len() {
        let sig = sigs_split[i].trim();
        if sig.len() > 0 {
            let s = EcdsaAdaptorSignature::from_str(sig)
                .map_err(|e| format!("Could not parse ECDSA adaptor signature {} {:?}", sig, e))?;
            sigs.push(s);
        }
    }
    if sigs.len() != num_cets as usize {
        return Err(format!(
            "Wrong number of signatures {} {}",
            sigs.len(),
            num_cets
        ));
    }

    let oracle_pubkey = pubkey_from_hex(oracle_pubkey_str)
        .map_err(|e| format!("Failed to parse oracle pubkey {}", e))?;
    let signing_pubkey = pubkey_from_hex(signing_pubkey_str)
        .map_err(|e| format!("Failed to parse signing pubkey {}", e))?;

    let res = global_lib().read().unwrap().verify_cet_adaptor_sigs(
        num_digits,
        num_cets,
        digit_string_template,
        &oracle_pubkey,
        &signing_pubkey,
        &nonces,
        &wcs,
        &shs,
        &sigs,
    );
    Ok(res.is_ok())
}

fn create_final_cet_sig_intern(
    pubkey_str: &str,
    num_digits: u8,
    oracle_signatures_str: &str,
    cet_value_wildcard: &str,
    cet_sighash_str: &str,
    adaptor_signature_str: &str,
) -> Result<String, String> {
    let pubkey =
        pubkey_from_hex(pubkey_str).map_err(|e| format!("Failed to parse other pubkey {}", e))?;

    let sigs_split: Vec<_> = oracle_signatures_str.split(" ").collect();
    let mut sigs = Vec::<SchnorrSignature>::with_capacity(sigs_split.len());
    for i in 0..sigs_split.len() {
        let sig_hex = sigs_split[i].trim();
        if sig_hex.len() > 0 {
            let sig = schnorr_sig_from_hex(&sig_hex)
                .map_err(|e| format!("Failed to parse element {} {}", i, e))?;
            sigs.push(sig);
        }
    }
    if sigs.len() != num_digits as usize {
        return Err(format!(
            "Wrong number of signatures {} {}",
            sigs.len(),
            num_digits
        ));
    }

    let cet_sighash =
        hash_from_hex(cet_sighash_str).map_err(|e| format!("Failed to parse sighash {}", e))?;

    let adaptor_signature_bin = Vec::from_hex(adaptor_signature_str)
        .map_err(|e| format!("Failed to parse adaptor sig {}", e))?;
    let adaptor_signature = EcdsaAdaptorSignature::from_slice(&adaptor_signature_bin)
        .map_err(|e| format!("Failed to parse adaptor sig {}", e))?;
    let sig = Lib::create_final_cet_sig(
        &pubkey,
        num_digits,
        &sigs,
        cet_value_wildcard,
        &cet_sighash,
        &adaptor_signature,
    )?;

    Ok(sig.to_lower_hex_string())
}

fn create_final_cet_sigs_intern(
    signing_key_index: u32,
    signing_pubkey_str: &str,
    other_pubkey_str: &str,
    num_digits: u8,
    oracle_signatures_str: &str,
    cet_value_wildcard: &str,
    cet_sighash_str: &str,
    other_adaptor_signature_str: &str,
) -> Result<String, String> {
    let signing_pubkey = pubkey_from_hex(signing_pubkey_str)
        .map_err(|e| format!("Failed to parse signing pubkey {}", e))?;
    let other_pubkey = pubkey_from_hex(other_pubkey_str)
        .map_err(|e| format!("Failed to parse other pubkey {}", e))?;

    let sigs_split: Vec<_> = oracle_signatures_str.split(" ").collect();
    let mut sigs = Vec::<SchnorrSignature>::with_capacity(sigs_split.len());
    for i in 0..sigs_split.len() {
        let sig_hex = sigs_split[i].trim();
        if sig_hex.len() > 0 {
            let sig = schnorr_sig_from_hex(&sig_hex)
                .map_err(|e| format!("Failed to parse element {} {}", i, e))?;
            sigs.push(sig);
        }
    }
    if sigs.len() != num_digits as usize {
        return Err(format!(
            "Wrong number of signatures {} {}",
            sigs.len(),
            num_digits
        ));
    }

    let cet_sighash =
        hash_from_hex(cet_sighash_str).map_err(|e| format!("Failed to parse sighash {}", e))?;

    let other_adaptor_signature_bin = Vec::from_hex(other_adaptor_signature_str)
        .map_err(|e| format!("Failed to parse other adaptor sig {}", e))?;
    let other_adaptor_signature =
        EcdsaAdaptorSignature::from_slice(&other_adaptor_signature_bin)
            .map_err(|e| format!("Failed to parse other adaptor sig {}", e))?;
    let (sig1, sig2) = global_lib().read().unwrap().create_final_cet_sigs(
        signing_key_index,
        &signing_pubkey,
        &other_pubkey,
        num_digits,
        &sigs,
        cet_value_wildcard,
        &cet_sighash,
        &other_adaptor_signature,
    )?;

    let sigs = format!(
        "{} {}",
        sig1.to_lower_hex_string(),
        sig2.to_lower_hex_string()
    );
    Ok(sigs)
}


// ##### Facade functions for C-style-interface invocations

/// Initialize the library, provide the secret as parameter. Return the XPUB.
#[no_mangle]
pub extern "C" fn init_with_entropy_c(entropy: *const c_char, network: *const c_char) -> *mut c_char {
    // Convert input parameter from raw pointer to Rust string
    let entropy_str = unsafe { CStr::from_ptr(entropy).to_str().unwrap_or("Error in entropy parameter") };
    let network_str = unsafe { CStr::from_ptr(network).to_str().unwrap_or("Error in network parameter") };

    match init_with_entropy_intern(entropy_str, network_str) {
        Ok(xpub) => {
            // Return as a C string
            CString::new(xpub).unwrap().into_raw()
        }
        Err(e) => {
            error_as_cstr_prefix(e)
        }
    }
}

/// Return a child public key (specified by its index).
#[no_mangle]
pub extern "C" fn get_public_key_c(index: u32) -> *mut c_char {
    match get_public_key_intern(index) {
        Ok(pubkey) => {
            // Return as a C string
            CString::new(pubkey).unwrap().into_raw()
        }
        Err(e) => {
            error_as_cstr_prefix(e)
        }
    }
}

/// Sign a hash with a child private key (specified by its index).
#[no_mangle]
pub extern "C" fn sign_hash_ecdsa_c(hash: *const c_char, signer_index: u32, signer_pubkey: *const c_char) -> *mut c_char {
    // Convert input parameter from raw pointer to Rust string
    let hash_str = unsafe { CStr::from_ptr(hash).to_str().unwrap_or("Error in hash parameter") };
    let signer_pubkey_str = unsafe { CStr::from_ptr(signer_pubkey).to_str().unwrap_or("Error in signer_pubkey parameter") };

    match sign_hash_ecdsa_intern(hash_str, signer_index, signer_pubkey_str) {
        Ok(sig) => {
            // Return as a C string
            CString::new(sig).unwrap().into_raw()
        }
        Err(e) => {
            error_as_cstr_prefix(e)
        }
    }
}

/// Create adaptor signatures for a number of CETs
#[no_mangle]
pub extern "C" fn create_cet_adaptor_sigs_c(
    num_digits: u8,
    num_cets: u32,
    digit_string_template: *const c_char,
    oracle_pubkey: *const c_char,
    signing_key_index: u32,
    signing_pubkey: *const c_char,
    nonces: *const c_char,
    interval_wildcards: *const c_char,
    sighashes: *const c_char,
) -> *mut c_char {
    // Convert input parameter from raw pointer to Rust string
    let digit_string_template_str = unsafe { CStr::from_ptr(digit_string_template).to_str().unwrap_or("Error in digit_string_template parameter") };
    let oracle_pubkey_str = unsafe { CStr::from_ptr(oracle_pubkey).to_str().unwrap_or("Error in oracle_pubkey parameter") };
    let signing_pubkey_str = unsafe { CStr::from_ptr(signing_pubkey).to_str().unwrap_or("Error in signing_pubkey parameter") };
    let nonces_str = unsafe { CStr::from_ptr(nonces).to_str().unwrap_or("Error in nonces parameter") };
    let interval_wildcards_str = unsafe { CStr::from_ptr(interval_wildcards).to_str().unwrap_or("Error in interval_wildcards parameter") };
    let sighashes_str = unsafe { CStr::from_ptr(sighashes).to_str().unwrap_or("Error in sighashes parameter") };

    match create_cet_adaptor_sigs_intern(num_digits, num_cets as u64, digit_string_template_str, oracle_pubkey_str, signing_key_index, signing_pubkey_str, nonces_str, interval_wildcards_str, sighashes_str) {
        Ok(sigs) => {
            // Return as a C string
            CString::new(sigs).unwrap().into_raw()
        }
        Err(e) => {
            error_as_cstr_prefix(e)
        }
    }
}

// #[no_mangle]
// pub extern "C" fn create_deterministic_nonce_c(
//     event_id: *const c_char,
//     index: u32,
// ) -> *mut c_char {
//     // Convert the event_id from raw pointer to Rust string
//     let event_id_str = unsafe { CStr::from_ptr(event_id).to_str().unwrap_or("Error in event ID") };

//     // Call your existing function that creates the nonce (assuming this is what you want)
//     match create_deterministic_nonce_intern(event_id_str, index) {
//         Ok((sk, pk)) => {
//             // Return as a C string
//             CString::new(format!("{} {}", sk, pk)).unwrap().into_raw()
//         },
//         Err(e) => {
//             error_as_cstr_prefix(e)
//         }
//     }
// }

// Additional C exports for Flutter wallet operations
#[no_mangle]
pub extern "C" fn get_xpub_c() -> *mut c_char {
    match get_xpub_intern() {
        Ok(xpub) => {
            CString::new(xpub).unwrap().into_raw()
        }
        Err(e) => {
            error_as_cstr_prefix(e)
        }
    }
}

#[no_mangle]
pub extern "C" fn get_address_c(index: u32) -> *mut c_char {
    match get_address_intern(index) {
        Ok(address) => {
            CString::new(address).unwrap().into_raw()
        }
        Err(e) => {
            error_as_cstr_prefix(e)
        }
    }
}

#[no_mangle]
pub extern "C" fn init_from_file_c(path: *const c_char, password: *const c_char) -> *mut c_char {
    let path_str = unsafe { CStr::from_ptr(path).to_str().unwrap_or("Error in path parameter") };
    let password_str = unsafe { CStr::from_ptr(password).to_str().unwrap_or("Error in password parameter") };

    match init_intern(path_str, password_str, false) {
        Ok(xpub) => {
            CString::new(xpub).unwrap().into_raw()
        }
        Err(e) => {
            error_as_cstr_prefix(e)
        }
    }
}

#[no_mangle]
pub extern "C" fn free_cstring(s: *mut c_char) {
    unsafe {
        if s.is_null() { return }
        let _ = CString::from_raw(s);
    }
}

// Return error with an "ERROR: " prefix, as a C string
fn error_as_cstr_prefix(error: String) -> *mut c_char {
    CString::new(format!("ERROR: {}", error)).unwrap().into_raw()
}


// ##### Facade functions for easy Python invocations (pyo3/maturin)

/// Initialize the library, load secret from encrypted file. Return the XPUB.
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn init(path_for_secret_file: String, encryption_password: String) -> PyResult<String> {
    init_intern(&path_for_secret_file, &encryption_password, false)
        .map_err(|e| PyErr::new::<PyException, _>(e))
}

#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn reinit_for_testing(
    path_for_secret_file: String,
    encryption_password: String,
) -> PyResult<String> {
    init_intern(&path_for_secret_file, &encryption_password, true)
        .map_err(|e| PyErr::new::<PyException, _>(e))
}

/// network: "bitcoin", or "signet".
// #[cfg(test)]
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn init_with_entropy(entropy: String, network: String) -> PyResult<String> {
    init_with_entropy_intern(&entropy, &network).map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Return the XPUB
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn get_xpub() -> PyResult<String> {
    get_xpub_intern().map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Return a child public key (specified by its index).
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn get_public_key(index: u32) -> PyResult<String> {
    get_public_key_intern(index).map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Return a child address (specified by index).
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn get_address(index: u32) -> PyResult<String> {
    get_address_intern(index).map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Verify a child public key.
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn verify_public_key(index: u32, pubkey: String) -> PyResult<bool> {
    verify_public_key_intern(index, &pubkey).map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Sign a hash with a child private key (specified by index).
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn sign_hash_ecdsa(hash: String, signer_index: u32, signer_pubkey: String) -> PyResult<String> {
    sign_hash_ecdsa_intern(&hash, signer_index, &signer_pubkey)
        .map_err(|e| PyErr::new::<PyException, _>(e))
}

// /// Create a nonce value deterministically
// #[cfg(feature = "with-pyo3")]
// #[pyfunction]
// pub fn create_deterministic_nonce(
//     event_id: String,
//     nonce_index: u32,
// ) -> PyResult<(String, String)> {
//     create_deterministic_nonce_intern(&event_id, nonce_index)
//         .map_err(|e| PyErr::new::<PyException, _>(e))
// }

/// Sign a message using Schnorr, with a nonce, using a child key
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn sign_schnorr_with_nonce(msg: String, nonce_sec_hex: String, index: u32) -> PyResult<String> {
    sign_schnorr_with_nonce_intern(&msg, &nonce_sec_hex, index)
        .map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Combine a number of public keys into one
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn combine_pubkeys(keys_hex: String) -> PyResult<String> {
    combine_pubkeys_intern(&keys_hex).map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Combine a number of secret keys into one.
/// Warning: Handle secret keys with caution!
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn combine_seckeys(keys_hex: String) -> PyResult<String> {
    combine_seckeys_intern(&keys_hex).map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Create adaptor signatures for a number of CETs
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn create_cet_adaptor_sigs(
    num_digits: u8,
    num_cets: u64,
    digit_string_template: String,
    oracle_pubkey: String,
    signing_key_index: u32,
    signing_pubkey: String,
    nonces: String,
    interval_wildcards: String,
    sighashes: String,
) -> PyResult<String> {
    create_cet_adaptor_sigs_intern(
        num_digits,
        num_cets,
        &digit_string_template,
        &oracle_pubkey,
        signing_key_index,
        &signing_pubkey,
        &nonces,
        &interval_wildcards,
        &sighashes,
    )
    .map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Verify adaptor signatures for a number of CETs
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn verify_cet_adaptor_sigs(
    num_digits: u8,
    num_cets: u64,
    digit_string_template: String,
    oracle_pubkey: String,
    signing_pubkey: String,
    nonces: String,
    interval_wildcards: String,
    sighashes: String,
    signatures: String,
) -> PyResult<bool> {
    verify_cet_adaptor_sigs_intern(
        num_digits,
        num_cets,
        &digit_string_template,
        &oracle_pubkey,
        &signing_pubkey,
        &nonces,
        &interval_wildcards,
        &sighashes,
        &signatures,
    )
    .map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Perform final signing of a CET, decrypt a signature when outcome signatures are available.
/// Return the decrypted signature.
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn create_final_cet_sig(
    pubkey: String,
    num_digits: u8,
    oracle_signatures: String,
    cet_value_wildcard: String,
    cet_sighash: String,
    adaptor_signature: String,
) -> PyResult<String> {
    create_final_cet_sig_intern(
        &pubkey,
        num_digits,
        &oracle_signatures,
        &cet_value_wildcard,
        &cet_sighash,
        &adaptor_signature,
    )
    .map_err(|e| PyErr::new::<PyException, _>(e))
}

/// Perform final signing of a CET, create the two signatures when outcome signatures are available.
/// Return the decrypted signature of the other, and my own signature (newly created).
#[cfg(feature = "with-pyo3")]
#[pyfunction]
pub fn create_final_cet_sigs(
    signing_key_index: u32,
    signing_pubkey: String,
    other_pubkey: String,
    num_digits: u8,
    oracle_signatures: String,
    cet_value_wildcard: String,
    cet_sighash: String,
    other_adaptor_signature: String,
) -> PyResult<String> {
    create_final_cet_sigs_intern(
        signing_key_index,
        &signing_pubkey,
        &other_pubkey,
        num_digits,
        &oracle_signatures,
        &cet_value_wildcard,
        &cet_sighash,
        &other_adaptor_signature,
    )
    .map_err(|e| PyErr::new::<PyException, _>(e))
}

#[cfg(feature = "with-pyo3")]
#[pymodule]
fn dlcplazacryptlib(_py: Python, m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(init, m)?)?;
    m.add_function(wrap_pyfunction!(reinit_for_testing, m)?)?;
    m.add_function(wrap_pyfunction!(init_with_entropy, m)?)?;
    m.add_function(wrap_pyfunction!(get_xpub, m)?)?;
    m.add_function(wrap_pyfunction!(get_public_key, m)?)?;
    m.add_function(wrap_pyfunction!(get_address, m)?)?;
    m.add_function(wrap_pyfunction!(verify_public_key, m)?)?;
    m.add_function(wrap_pyfunction!(sign_hash_ecdsa, m)?)?;
    // m.add_function(wrap_pyfunction!(create_deterministic_nonce, m)?)?;
    m.add_function(wrap_pyfunction!(sign_schnorr_with_nonce, m)?)?;
    m.add_function(wrap_pyfunction!(combine_pubkeys, m)?)?;
    m.add_function(wrap_pyfunction!(combine_seckeys, m)?)?;
    m.add_function(wrap_pyfunction!(create_cet_adaptor_sigs, m)?)?;
    m.add_function(wrap_pyfunction!(verify_cet_adaptor_sigs, m)?)?;
    m.add_function(wrap_pyfunction!(create_final_cet_sig, m)?)?;
    m.add_function(wrap_pyfunction!(create_final_cet_sigs, m)?)?;
    Ok(())
}


