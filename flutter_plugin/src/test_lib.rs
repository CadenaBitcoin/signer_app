// Copyright (c) 2025-present Cadena Bitcoin
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

use dlccryptlib::{create_deterministic_nonce, get_public_key, init_with_entropy, sign_hash_ecdsa};

const DUMMY_ENTROPY_STR: &str = "0000000000000000000000000000000000000000000000000000000000000000";
const NETWORK_SIGNET: &str = "signet";
const DEFAULT_NETWORK: &str = NETWORK_SIGNET;

fn dummy_bytes32(last_byte: u8) -> String {
    format!(
        "00000000000000000000000000000000000000000000000000000000000000{:02x}",
        last_byte
    )
}

fn dummy_entropy() -> String {
    dummy_bytes32(0)
}

#[test]
fn test_init_with_entropy() {
    let xpub = init_with_entropy(DUMMY_ENTROPY_STR, DEFAULT_NETWORK).unwrap();
    assert_eq!(
            xpub,
            "tpubDCWivZp6qaqCALCt8MyLqAb3awnWm4hfbBPjdZqirYFXYeZ5YsfbWVaPacULZTGtK1RPBSZ92UWNjnhL4fB9UVrF2FjgW8cgmBjxPBmB4iB"
        );
}

#[test]
fn test_get_public_key() {
    let _xpub = init_with_entropy(DUMMY_ENTROPY_STR, DEFAULT_NETWORK).unwrap();

    let pubkey0 = get_public_key(0, 0).unwrap();
    assert_eq!(
        pubkey0.to_string(),
        "0298720ece754e377af1b2716256e63c2e2427ff6ebdc66c2071c43ae80132ca32"
    );

    let pubkey3 = get_public_key(0, 3).unwrap();
    assert_eq!(
        pubkey3.to_string(),
        "03b74dc470965932fc976459096526b08a0f939a95e4b72db8f9aadce18a08a72e"
    );
}

#[test]
fn test_sign_hash_ecdsa() {
    let _xpub = init_with_entropy(&dummy_entropy(), DEFAULT_NETWORK).unwrap();

    let pubkey3 = get_public_key(0, 3).unwrap();
    assert_eq!(
        pubkey3.to_string(),
        "03b74dc470965932fc976459096526b08a0f939a95e4b72db8f9aadce18a08a72e"
    );

    let hash = dummy_bytes32(7);
    let _sig = sign_hash_ecdsa(&hash, 0, 3, &pubkey3).unwrap();

    // negative test, wrong index
    assert!(sign_hash_ecdsa(&hash, 0, 31, &pubkey3).is_err());
}

#[test]
fn test_create_deterministic_nonce() {
    let (sk1, pk1) = create_deterministic_nonce("event01", 0).unwrap();
    assert_eq!(sk1.len(), 64);
    assert_eq!(pk1.len(), 66);
    assert_ne!(sk1, pk1);
    let (sk2, pk2) = create_deterministic_nonce("event01", 1).unwrap();
    assert_ne!(sk1, sk2);
    assert_ne!(pk1, pk2);
}
