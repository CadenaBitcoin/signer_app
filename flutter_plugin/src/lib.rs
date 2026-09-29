// Copyright (c) 2025-present Cadena Bitcoin
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#[cfg(test)]
mod test_lib;

#[cfg(feature = "with-pyo3")]
use dlccryptlib_py;

// Conditional compilation to exclude PyO3-related code for Android
#[cfg(feature = "with-pyo3")]
use pyo3::prelude::*;
#[cfg(feature = "with-pyo3")]
use pyo3::wrap_pyfunction;

#[cfg(feature = "with-pyo3")]
#[pymodule]
fn dlcplazacryptlib(_py: Python, m: &Bound<'_, PyModule>) -> PyResult<()> {
    // m.add_function(wrap_pyfunction!(init, m)?)?;
    // m.add_function(wrap_pyfunction!(reinit_for_testing, m)?)?;
    m.add_function(wrap_pyfunction!(dlccryptlib_py::init_with_entropy, m)?)?;
    m.add_function(wrap_pyfunction!(dlccryptlib_py::get_xpub, m)?)?;
    m.add_function(wrap_pyfunction!(dlccryptlib_py::get_public_key, m)?)?;
    m.add_function(wrap_pyfunction!(dlccryptlib_py::get_address, m)?)?;
    // m.add_function(wrap_pyfunction!(verify_public_key, m)?)?;
    m.add_function(wrap_pyfunction!(dlccryptlib_py::sign_hash_ecdsa, m)?)?;
    m.add_function(wrap_pyfunction!(
        dlccryptlib_py::create_deterministic_nonce,
        m
    )?)?;
    // m.add_function(wrap_pyfunction!(sign_schnorr_with_nonce, m)?)?;
    // m.add_function(wrap_pyfunction!(combine_pubkeys, m)?)?;
    // m.add_function(wrap_pyfunction!(combine_seckeys, m)?)?;
    m.add_function(wrap_pyfunction!(
        dlccryptlib_py::create_cet_adaptor_sigs,
        m
    )?)?;
    // m.add_function(wrap_pyfunction!(verify_cet_adaptor_sigs, m)?)?;
    // m.add_function(wrap_pyfunction!(create_final_cet_sigs, m)?)?;
    Ok(())
}
