import dlcplazacryptlib

xpub = dlcplazacryptlib.init('sample_secret.sec', 'password')
print('Library initialized, xpub', xpub)

xpub = dlcplazacryptlib.get_xpub()
print('Xpub', xpub)
pubkey0 = dlcplazacryptlib.get_public_key(0)
print('Pubkey 0', pubkey0)
address0 = dlcplazacryptlib.get_address(0)
print('Address 0', address0)

# event_id = "event001"
# nonce0_arr = dlcplazacryptlib.create_deterministic_nonce(event_id, 0)
# nonce0_pub = nonce0_arr[1]
# print('Nonce 0 (pub)', nonce0_pub)
# nonce1_arr = dlcplazacryptlib.create_deterministic_nonce(event_id, 1)
# nonce1_sec = nonce1_arr[0]
# nonce1_pub = nonce1_arr[1]
# print('Nonce 1 (pub, sec)', nonce1_pub, nonce1_sec)
# nonce2_arr = dlcplazacryptlib.create_deterministic_nonce(event_id, 2)

# # Sign the event id with nonce1
# sig = dlcplazacryptlib.sign_schnorr_with_nonce(event_id, nonce1_sec, 0)
# print('Signature:  ', sig)

# # Sign again (same nonce)
# print('Sign again: ', dlcplazacryptlib.sign_schnorr_with_nonce(event_id, nonce1_sec, 0))

# # Sign with different nonce
# print('Sign with other nonce: ', dlcplazacryptlib.sign_schnorr_with_nonce(event_id, nonce2_arr[0], 0))

# nonces_pub = nonce0_pub + " " + nonce1_pub + " " + nonce2_arr[1]
# print("Combining pub nonces:", nonces_pub)
# combined_nonce_pub = dlcplazacryptlib.combine_pubkeys(nonces_pub)
# print('Combined pub nonce:', combined_nonce_pub)

# nonces_sec = nonce0_arr[0] + " " + nonce1_arr[0] + " " + nonce2_arr[0]
# print("Combining sec nonces:", nonces_sec)
# combined_nonce_sec = dlcplazacryptlib.combine_seckeys(nonces_sec)
# print('Combined sec nonce:', combined_nonce_sec)
