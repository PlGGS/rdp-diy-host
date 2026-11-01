#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use librustdesk::*;

#[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
fn main() {
    if !common::global_init() {
        eprintln!("Global initialization failed.");
        return;
    }
    common::test_rendezvous_server();
    common::test_nat_type();
    common::global_clean();
}

#[cfg(not(any(
    target_os = "android",
    target_os = "ios",
    feature = "flutter"
)))]
fn main() {
    #[cfg(all(windows, not(feature = "inline")))]
    unsafe {
        winapi::um::shellscalingapi::SetProcessDpiAwareness(2);
    }
    #[cfg(feature = "rdpdiy")]
    rdpdiy::init();
    if let Some(args) = crate::core_main::core_main().as_mut() {
        #[cfg(feature = "rdpdiy")]
        rdpdiy::no_ui(args);
        #[cfg(not(feature = "rdpdiy"))]
        ui::start(args);
    }
    common::global_clean();
}
