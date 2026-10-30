//! C ABI over the engine's command contract.
//!
//! A native UI owns an opaque [`RlSession`] and talks to it with JSON only:
//! `rl_execute(session, "develop.set", "{\"control\":\"light.exposure\",\"value\":0.35}")`.
//! Every returned string is owned by the caller and released with [`rl_string_free`].
//! Replies are `{"ok": <value>}` or `{"error": "<message>"}`; nothing here panics across the FFI.

use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};

use lightcraft_engine::Session;
use serde_json::{Value, json};

/// Opaque session handle.
pub struct RlSession(Session);

fn reply(v: Value) -> *mut c_char {
    // JSON text never contains an interior NUL, so this cannot fail.
    CString::new(v.to_string()).map_or(std::ptr::null_mut(), CString::into_raw)
}

/// New empty session (`demo` non-zero loads the generated demo library).
#[unsafe(no_mangle)]
pub extern "C" fn rl_session_new(demo: i32) -> *mut RlSession {
    let s = catch_unwind(|| {
        let base = if demo != 0 { Session::with_demo() } else { Session::new() };
        base.with_fs().with_default_denoise_models().with_system_clock()
    });
    match s {
        Ok(s) => Box::into_raw(Box::new(RlSession(s))),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Run command `id` with JSON `params` (null or empty means no params).
///
/// # Safety
/// `session` must come from [`rl_session_new`]; `id` and `params` must be NUL-terminated or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_execute(session: *mut RlSession, id: *const c_char, params: *const c_char) -> *mut c_char {
    let Some(session) = (unsafe { session.as_mut() }) else {
        return reply(json!({"error": "null session"}));
    };
    if id.is_null() {
        return reply(json!({"error": "null command id"}));
    }
    let Ok(id) = unsafe { CStr::from_ptr(id) }.to_str() else {
        return reply(json!({"error": "command id is not UTF-8"}));
    };
    let params: Value = if params.is_null() {
        Value::Null
    } else {
        match unsafe { CStr::from_ptr(params) }.to_str().map(|t| if t.trim().is_empty() { Ok(Value::Null) } else { serde_json::from_str(t) }) {
            Ok(Ok(v)) => v,
            Ok(Err(e)) => return reply(json!({"error": format!("bad params JSON: {e}")})),
            Err(_) => return reply(json!({"error": "params are not UTF-8"})),
        }
    };
    match catch_unwind(AssertUnwindSafe(|| session.0.execute(id, &params))) {
        Ok(Ok(v)) => reply(json!({"ok": v})),
        Ok(Err(e)) => reply(json!({"error": e.to_string()})),
        Err(_) => reply(json!({"error": "internal panic"})),
    }
}

/// # Safety
/// `session` must come from [`rl_session_new`] and not be used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_session_free(session: *mut RlSession) {
    if !session.is_null() {
        drop(unsafe { Box::from_raw(session) });
    }
}

/// # Safety
/// `s` must be a string returned by this library, freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rl_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(unsafe { CString::from_raw(s) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn call(s: *mut RlSession, id: &str, params: &str) -> Value {
        let (id, params) = (CString::new(id).unwrap(), CString::new(params).unwrap());
        let r = unsafe { rl_execute(s, id.as_ptr(), params.as_ptr()) };
        let v = serde_json::from_str(unsafe { CStr::from_ptr(r) }.to_str().unwrap()).unwrap();
        unsafe { rl_string_free(r) };
        v
    }

    #[test]
    fn unknown_command_is_an_error_not_a_crash() {
        let s = rl_session_new(1);
        assert!(call(s, "no.such.command", "{}").get("error").is_some());
        assert!(call(s, "develop.set", "{not json").get("error").is_some());
        unsafe { rl_session_free(s) };
    }

    #[test]
    fn null_session_is_reported() {
        let id = CString::new("x").unwrap();
        let r = unsafe { rl_execute(std::ptr::null_mut(), id.as_ptr(), std::ptr::null()) };
        unsafe { rl_string_free(r) };
    }
}
