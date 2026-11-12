use crate::adaptor_signature::verify_ecdsa_signature;
use crate::{
    combine_pubkeys_intern, combine_seckeys_intern, /* create_deterministic_nonce_intern, */
    get_public_key_intern, init_with_entropy, init_with_entropy_intern, keypair_from_sec_key_hex,
    sign_schnorr_with_nonce_intern, verify_public_key_intern, Lib,
};
use bitcoin::hex::FromHex;
use bitcoin::secp256k1::PublicKey;

const DUMMY_ENTROPY_STR: &str = "0000000000000000000000000000000000000000000000000000000000000000";
const NETWORK_MAINNET: &str = "bitcoin";
const NETWORK_SIGNET: &str = "signet";
const DEFAULT_NETWORK: &str = NETWORK_SIGNET;

fn dummy_bytes32(last_byte: u8) -> [u8; 32] {
    let mut b = [0; 32];
    b[31] = last_byte;
    b
}

fn dummy_entropy() -> Vec<u8> {
    dummy_bytes32(0).to_vec()
}

#[test]
fn test_init_with_entropy_lib() {
    let mut lib = Lib::new_empty();
    let _ = lib
        .init_with_entropy(&dummy_entropy(), DEFAULT_NETWORK)
        .unwrap();
    let xpub = lib.get_xpub().unwrap().to_string();
    assert_eq!(
            xpub,
            "tpubDCWivZp6qaqCALCt8MyLqAb3awnWm4hfbBPjdZqirYFXYeZ5YsfbWVaPacULZTGtK1RPBSZ92UWNjnhL4fB9UVrF2FjgW8cgmBjxPBmB4iB"
        );
}

#[test]
fn test_init_with_entropy_intern() {
    let xpub = init_with_entropy_intern(DUMMY_ENTROPY_STR, DEFAULT_NETWORK).unwrap();
    assert_eq!(
            xpub,
            "tpubDCWivZp6qaqCALCt8MyLqAb3awnWm4hfbBPjdZqirYFXYeZ5YsfbWVaPacULZTGtK1RPBSZ92UWNjnhL4fB9UVrF2FjgW8cgmBjxPBmB4iB"
        );
}

#[test]
fn test_init_with_entropy() {
    let xpub =
        init_with_entropy(DUMMY_ENTROPY_STR.to_string(), DEFAULT_NETWORK.to_string()).unwrap();
    assert_eq!(
            xpub,
            "tpubDCWivZp6qaqCALCt8MyLqAb3awnWm4hfbBPjdZqirYFXYeZ5YsfbWVaPacULZTGtK1RPBSZ92UWNjnhL4fB9UVrF2FjgW8cgmBjxPBmB4iB"
        );
}

#[test]
fn test_init_with_entropy_lib_mainnet() {
    let mut lib = Lib::new_empty();
    let _ = lib
        .init_with_entropy(&dummy_entropy(), NETWORK_MAINNET)
        .unwrap();
    let xpub = lib.get_xpub().unwrap().to_string();
    assert_eq!(
            xpub,
            "xpub6Bner3L3tdQW367NmmMsWKtMfP7hbu4JxdtbSGdWWjSzLkSUEnT7G9h5GFWUXtifeRhHiUXJuek1qeaTJqnXkveWpiHp8rmt53E8HTMshg9"
        );
}

#[test]
fn test_get_public_key() {
    let _xpub = init_with_entropy_intern(DUMMY_ENTROPY_STR, DEFAULT_NETWORK).unwrap();

    let pubkey0 = get_public_key_intern(0).unwrap();
    assert_eq!(
        pubkey0.to_string(),
        "0298720ece754e377af1b2716256e63c2e2427ff6ebdc66c2071c43ae80132ca32"
    );

    let pubkey3 = get_public_key_intern(3).unwrap();
    assert_eq!(
        pubkey3.to_string(),
        "03b74dc470965932fc976459096526b08a0f939a95e4b72db8f9aadce18a08a72e"
    );
}

#[test]
fn test_verify_public_key() {
    let _xpub = init_with_entropy_intern(DUMMY_ENTROPY_STR, DEFAULT_NETWORK).unwrap();

    assert!(verify_public_key_intern(
        0,
        "0298720ece754e377af1b2716256e63c2e2427ff6ebdc66c2071c43ae80132ca32"
    )
    .unwrap());
    assert_eq!(verify_public_key_intern(0, "03b74dc470965932fc976459096526b08a0f939a95e4b72db8f9aadce18a08a72e").err().unwrap(),
            "Pubkey mismatch, index 0, 03b74dc470965932fc976459096526b08a0f939a95e4b72db8f9aadce18a08a72e vs. 0298720ece754e377af1b2716256e63c2e2427ff6ebdc66c2071c43ae80132ca32");
    assert!(verify_public_key_intern(
        3,
        "03b74dc470965932fc976459096526b08a0f939a95e4b72db8f9aadce18a08a72e"
    )
    .unwrap());
    assert_eq!(verify_public_key_intern(3, "0298720ece754e377af1b2716256e63c2e2427ff6ebdc66c2071c43ae80132ca32").err().unwrap(),
            "Pubkey mismatch, index 3, 0298720ece754e377af1b2716256e63c2e2427ff6ebdc66c2071c43ae80132ca32 vs. 03b74dc470965932fc976459096526b08a0f939a95e4b72db8f9aadce18a08a72e");
}

#[test]
fn test_sign_hash_ecdsa() {
    let mut lib = Lib::new_empty();
    let _xpub = lib
        .init_with_entropy(&dummy_entropy(), DEFAULT_NETWORK)
        .unwrap();

    let pubkey3 = lib.get_child_public_key(3).unwrap();
    assert_eq!(
        pubkey3.to_string(),
        "03b74dc470965932fc976459096526b08a0f939a95e4b72db8f9aadce18a08a72e"
    );

    let hash = dummy_bytes32(7);
    let sig = lib.sign_hash_ecdsa(&hash, 3, &pubkey3).unwrap();

    // verify_signature
    let verif_res = verify_ecdsa_signature(&hash, &sig, &pubkey3, true).unwrap();
    assert!(verif_res);

    // negative test, wrong index
    assert!(lib.sign_hash_ecdsa(&hash, 31, &pubkey3).is_err());
}

// #[test]
// fn test_create_deterministic_nonce() {
//     let (sk1, pk1) = create_deterministic_nonce_intern("event01", 0).unwrap();
//     assert_eq!(sk1.len(), 64);
//     assert_eq!(pk1.len(), 66);
//     assert_ne!(sk1, pk1);
//     let (sk2, pk2) = create_deterministic_nonce_intern("event01", 1).unwrap();
//     assert_ne!(sk1, sk2);
//     assert_ne!(pk1, pk2);
// }

#[test]
fn test_sign_schnorr_with_nonce() {
    let _xpub = init_with_entropy_intern(DUMMY_ENTROPY_STR, DEFAULT_NETWORK).unwrap();

    let msg = "This is a message";
    let nonce = "0123450000000000006897528962743076432965432697856340567500000100";
    let sig = sign_schnorr_with_nonce_intern(msg, nonce, 0).unwrap();
    let expected_sig = "ff4cb99e0a9be8ec7dea1e51904cf22f71717c19fc3e7dcbc8346eb28bebffbb892c4c41e05c2383efda00f5acc9c7f3622d88a90630cd62d49db598c8ce10b9";
    assert_eq!(sig.len(), 128);
    assert_eq!(sig.to_string(), expected_sig);

    // sign again
    let sig2 = sign_schnorr_with_nonce_intern(msg, nonce, 0).unwrap();
    assert_eq!(sig2.to_string(), expected_sig);

    // sign with different nonce
    let nonce2 = "0123450000000000006897528962743076432965432697856340567500000199";
    let sig3 = sign_schnorr_with_nonce_intern(msg, nonce2, 0).unwrap();
    assert_eq!(sig3.to_string(), "4578740620e7a2c56eabea07c835dba35e832115930d023d0a7778652fbbf7d97a9f4a207dcb1456f1b0f57c4856085c32c79f4efce81cd276c272190aab5e3c");
}

fn create_dummy_pubkey(index: u8) -> PublicKey {
    let sechex = format!(
        "012345000000000000689752896274307643296543269785634056750000000{}",
        index
    );
    assert_eq!(sechex.len(), 64);
    let keypair = keypair_from_sec_key_hex(&sechex).unwrap();
    keypair.public_key()
}

#[test]
fn test_combine_pubkeys() {
    let mut input_str = String::new();
    for i in 0..3 {
        input_str += &(create_dummy_pubkey(i).to_string() + " ");
    }
    let combined = combine_pubkeys_intern(&input_str).unwrap();
    assert_eq!(
        combined,
        "030d7a38fb6eab9933efd3149f7ce0c466e93eb0680442856acb664719b60ae977"
    );
}

#[test]
fn test_combine_seckeys() {
    let input_str = "0123450000000000006897528962743076432965432697856340567500000100 \
            0123450000000000006897528962743076432965432697856340567500000200 \
            0123450000000000006897528962743076432965432697856340567500000300";
    let combined = combine_seckeys_intern(input_str).unwrap();
    assert_eq!(
        combined,
        "0369cf00000000000139c5f79c275c9162c97c2fc973c69029c1035f00000600"
    );
}

#[test]
fn test_create_cet_adaptor_sigs() {
    let mut lib = Lib::new_empty();
    let _xpub = lib.init_with_entropy(&dummy_bytes32(0).to_vec(), DEFAULT_NETWORK);

    let nonces = vec![
        create_dummy_pubkey(0),
        create_dummy_pubkey(1),
        create_dummy_pubkey(2),
        create_dummy_pubkey(3),
        create_dummy_pubkey(4),
        create_dummy_pubkey(5),
    ];
    let interval_wildcards = vec![
        "001****".to_string(),
        "002****".to_string(),
        "003****".to_string(),
    ];
    let sighashes = vec![dummy_bytes32(0), dummy_bytes32(1), dummy_bytes32(2)];
    let oracle_pubkey = create_dummy_pubkey(9);
    let my_pubkey = lib.get_child_public_key(0).unwrap();
    assert_eq!(
        my_pubkey.to_string(),
        "0298720ece754e377af1b2716256e63c2e2427ff6ebdc66c2071c43ae80132ca32"
    );

    let adaptor_sigs_vec = lib
        .create_cet_adaptor_sigs(
            6, // num_digits
            3, // num_cets
            "Outcome:btcusd1741474920:{digit_index}:{digit_outcome}",
            &oracle_pubkey,
            0,
            &my_pubkey,
            &nonces,
            &interval_wildcards,
            &sighashes,
        )
        .unwrap();
    assert_eq!(adaptor_sigs_vec.len(), 3);
    // adaptor sigs are variable, cannot assert
}

#[test]
fn test_verify_cet_adaptor_sigs() {
    let mut lib = Lib::new_empty();
    let _xpub = lib.init_with_entropy(&dummy_bytes32(0).to_vec(), DEFAULT_NETWORK);

    let nonces = vec![
        create_dummy_pubkey(0),
        create_dummy_pubkey(1),
        create_dummy_pubkey(2),
        create_dummy_pubkey(3),
        create_dummy_pubkey(4),
        create_dummy_pubkey(5),
    ];
    let interval_wildcards = vec![
        "001****".to_string(),
        "002****".to_string(),
        "003****".to_string(),
    ];
    let sighashes = vec![dummy_bytes32(0), dummy_bytes32(1), dummy_bytes32(2)];
    let oracle_pubkey = create_dummy_pubkey(9);
    let my_pubkey = lib.get_child_public_key(0).unwrap();
    assert_eq!(
        my_pubkey.to_string(),
        "0298720ece754e377af1b2716256e63c2e2427ff6ebdc66c2071c43ae80132ca32"
    );

    // First create the signatures
    let adaptor_sigs_vec = lib
        .create_cet_adaptor_sigs(
            6, // num_digits
            3, // num_cets
            "Outcome:btcusd1741474920:{digit_index}:{digit_outcome}",
            &oracle_pubkey,
            0,
            &my_pubkey,
            &nonces,
            &interval_wildcards,
            &sighashes,
        )
        .unwrap();
    assert_eq!(adaptor_sigs_vec.len(), 3);

    // Verify the signatures
    let _res = lib
        .verify_cet_adaptor_sigs(
            6,
            3,
            "Outcome:btcusd1741474920:{digit_index}:{digit_outcome}",
            &oracle_pubkey,
            &my_pubkey,
            &nonces,
            &interval_wildcards,
            &sighashes,
            &adaptor_sigs_vec,
        )
        .unwrap();
}

#[test]
fn test_create_final_cet_sigs() {
    let event_id = "btcusd1741474920";
    let digits_template_string = "Outcome:btcusd1741474920:{digit_index}:{digit_outcome}";
    let digits = 4 as u8;
    let final_cet_wildcard = "9534";
    let sighash = dummy_bytes32(7);

    // First preparation: create oracle signatures
    let mut lib_ora = Lib::new_empty();
    let _xpub = lib_ora.init_with_entropy(&dummy_bytes32(3).to_vec(), DEFAULT_NETWORK);
    let oracle_pubkey = lib_ora.get_child_public_key(0).unwrap();
    assert_eq!(
        oracle_pubkey.to_string(),
        "020a5e571a47cc259d3cc0454a8b7e58bba16e01156bb72d0ce490823f51117cce"
    );

    // Prepare nonces
    let mut nonces_sec_vec = Vec::new();
    let mut nonces_pub_vec = Vec::new();
    let mut nonces = String::new();
    // for i in 0..(digits as usize) {
    //     let (nsec, npub) = lib_ora
    //         .create_deterministic_nonce(event_id, i as u32)
    //         .unwrap();
    //     nonces_sec_vec.push(<[u8; 32]>::from_hex(&nsec).unwrap());
    //     nonces_pub_vec.push(npub.clone());
    //     nonces += &format!("{} ", npub);
    // }
    // Fixed oracle nonces (test data); the assertion below pins their public keys
    let nonce_secs = [
        "b68b2cf92663608ff438356debff62dbcab63a7138550b7cf294abd656e81721",
        "613f517d7cc6a91ea92750eff554f37b433bd70431a1e810baa77e9be4f64d64",
        "55c44293eb2e2daacf1c794503809f51a1b1c464ced6ea506a9744e87867a3a7",
        "01a4ee8791fc54eda1aea9dc8c392ae950c5712a5d6c3bdea66e6b51fa7b598d",
    ];
    let secp = bitcoin::key::Secp256k1::new();
    for nsec_hex in nonce_secs {
        let nsec = <[u8; 32]>::from_hex(nsec_hex).unwrap();
        let npub = bitcoin::secp256k1::SecretKey::from_slice(&nsec)
            .unwrap()
            .public_key(&secp);
        nonces_sec_vec.push(nsec);
        nonces_pub_vec.push(npub);
        nonces += &format!("{} ", npub);
    }
    assert_eq!(nonces, "03829589a7db8530b521577ce5b9560e31cb29b943927b417c580ec3b6e57317a9 0278d6b6808d5370da62c9304f66415c1f9f408a2ee9d95a9dc836512218a7b04f 027c14675c2bd2e728e5760d5017d4ae2b22a4a33193689654e5eb13111ab7f491 02e7657c7d006d27b248642974875348b41299690a6415bc019ac71e6988434daa ");

    let mut oracle_signatures = Vec::new();
    for i in 0..(digits as usize) {
        let digit_value = final_cet_wildcard.chars().collect::<Vec<_>>()[i as usize];
        let digit_string = digits_template_string
            .replace("{digit_index}", &format!("{}", i))
            .replace("{digit_outcome}", &format!("{}", digit_value));
        let sig = lib_ora
            .sign_schnorr_with_nonce(&digit_string, &nonces_sec_vec[i], 0)
            .unwrap();
        oracle_signatures.push(sig);
    }

    // Second, create adaptor sig of other
    let mut lib2 = Lib::new_empty();
    let _xpub = lib2
        .init_with_entropy(&dummy_bytes32(2).to_vec(), DEFAULT_NETWORK)
        .unwrap();
    let other_pubkey = lib2.get_child_public_key(0).unwrap();
    assert_eq!(
        other_pubkey.to_string(),
        "02142c5af97c4afd91bea47ac47e56fad2935dcacc04b3ffa69e5ff7760cbd07ed"
    );

    // only use one CET
    let other_adaptor_sigs_vec = lib2
        .create_cet_adaptor_sigs(
            digits,
            1, // num_cets
            digits_template_string,
            &oracle_pubkey,
            0,
            &other_pubkey,
            &nonces_pub_vec,
            &vec![final_cet_wildcard.to_string()], // interval_wildcards
            &vec![sighash],
        )
        .unwrap();
    let other_adaptor_sig = other_adaptor_sigs_vec[0];
    // adator sig is variable, cannot assert
    assert_eq!(other_adaptor_sig.to_string().len(), 324);

    // Now back to ourselves
    let mut lib1 = Lib::new_empty();
    let _xpub = lib1
        .init_with_entropy(&dummy_bytes32(1).to_vec(), DEFAULT_NETWORK)
        .unwrap();
    let my_pubkey = lib1.get_child_public_key(0).unwrap();
    assert_eq!(
        my_pubkey.to_string(),
        "035bcac7323e9971268213a188d8268277abcd962cdf096e68e2b58c228216f104"
    );

    let final_sigs = lib1
        .create_final_cet_sigs(
            0,
            &my_pubkey,
            &other_pubkey,
            digits,
            &oracle_signatures,
            final_cet_wildcard,
            &sighash,
            &other_adaptor_sig,
        )
        .unwrap();
    let sig_of_other = final_sigs.0;
    let my_sig = final_sigs.1;

    // verify_signatures
    let verif_res1 = verify_ecdsa_signature(&sighash, &sig_of_other, &other_pubkey, true).unwrap();
    assert!(verif_res1);
    let verif_res2 = verify_ecdsa_signature(&sighash, &my_sig, &my_pubkey, true).unwrap();
    assert!(verif_res2);
}
