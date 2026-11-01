//! rdp.diy Host: a headless build of RustDesk's background service, managed from the rdp.diy
//! web console. Enabled with `--features rdpdiy`; without the feature nothing here is compiled.
//!
//! Server settings are fixed at build time so the host can only ever register with the
//! rdp.diy deployment it was built for:
//!
//! | Build env             | Default            |
//! |-----------------------|--------------------|
//! | `RDPDIY_ID_SERVER`    | `rdp.diy`          |
//! | `RDPDIY_RELAY_SERVER` | `rdp.diy:21117`    |
//! | `RDPDIY_API_SERVER`   | `https://rdp.diy`  |
//! | `RDPDIY_KEY`          | (none; required for release builds) |

use base::config::keys;
use hbb_common::config;

pub const APP_NAME: &str = "rdpdiy-host";
pub const DISPLAY_NAME: &str = "rdp.diy Host";
#[cfg(target_os = "macos")]
const ORG: &str = "diy.rdp";

const ID_SERVER: &str = match option_env!("RDPDIY_ID_SERVER") {
    Some(v) => v,
    None => "rdp.diy",
};
const RELAY_SERVER: &str = match option_env!("RDPDIY_RELAY_SERVER") {
    Some(v) => v,
    None => "rdp.diy:21117",
};
const API_SERVER: &str = match option_env!("RDPDIY_API_SERVER") {
    Some(v) => v,
    None => "https://rdp.diy",
};
const KEY: &str = match option_env!("RDPDIY_KEY") {
    Some(v) => v,
    None => "",
};

/// Must run before anything reads the config: the app name decides the config, log and IPC paths.
pub fn init() {
    *config::APP_NAME.write().unwrap() = APP_NAME.to_owned();
    #[cfg(target_os = "macos")]
    {
        *config::ORG.write().unwrap() = ORG.to_owned();
    }

    let mut overwrite = config::OVERWRITE_SETTINGS.write().unwrap();
    for (k, v) in [
        (keys::OPTION_CUSTOM_RENDEZVOUS_SERVER, ID_SERVER),
        (keys::OPTION_RELAY_SERVER, RELAY_SERVER),
        (keys::OPTION_API_SERVER, API_SERVER),
        (keys::OPTION_KEY, KEY),
        // RustDesk's updater would replace this build with stock RustDesk.
        (keys::OPTION_ALLOW_AUTO_UPDATE, "N"),
    ] {
        if !v.is_empty() {
            overwrite.insert(k.to_owned(), v.to_owned());
        }
    }
    drop(overwrite);

    // No UI: nobody is there to click "accept", so sessions are password-only by default.
    // Team policies pushed from the console can still change these.
    let mut defaults = config::DEFAULT_SETTINGS.write().unwrap();
    defaults.insert(keys::OPTION_APPROVE_MODE.to_owned(), "password".to_owned());
    defaults.insert(
        keys::OPTION_VERIFICATION_METHOD.to_owned(),
        "use-permanent-password".to_owned(),
    );
    drop(defaults);

    config::BUILTIN_SETTINGS
        .write()
        .unwrap()
        .insert(keys::OPTION_HIDE_TRAY.to_owned(), "Y".to_owned());
}

/// Called where RustDesk would open its UI.
pub fn no_ui(args: &[String]) {
    if args.first().map(String::as_str) == Some("--cm") {
        run_headless_cm();
        return;
    }
    #[cfg(target_os = "macos")]
    if args.first().map(String::as_str) == Some("--permissions") {
        request_permissions();
        return;
    }
    // Opened from Finder, or by System Settings' "Quit & Reopen" after a permission change.
    #[cfg(target_os = "macos")]
    if args.is_empty() && !std::io::IsTerminal::is_terminal(&std::io::stdin()) {
        restart_agent();
        request_permissions();
        return;
    }
    println!(
        "{DISPLAY_NAME} {}\n\
         \n\
         Lets this computer be controlled from the rdp.diy web console.\n\
         Based on RustDesk (AGPL-3.0): https://github.com/PlGGS/rdp-diy-host\n\
         \n\
         Usage: {APP_NAME} <command>\n\
         \x20 --deploy --token <token>   Enroll this computer in your team (token from Add a device)\n\
         \x20 --get-id                   Print this computer's ID\n\
         \x20 --password <password>      Set the permanent password (as root)\n\
         \x20 --install-service          Install and start the background service (as root)\n\
         \x20 --uninstall-service        Remove the background service (as root)\n\
         \x20 --service                  Run the service (used by systemd/launchd/SCM)\n\
         \x20 --server                   Run the session server in the current desktop session\n\
         \x20 --permissions              macOS: ask for Screen Recording and Accessibility access\n\
         \n\
         ID server: {ID_SERVER}\n\
         API: {API_SERVER}",
        crate::VERSION
    );
}

/// macOS ties privacy permissions to the app that asks, so the installer launches this through
/// LaunchServices (`open -a`) for the prompts to name rdp.diy Host rather than Terminal.
#[cfg(target_os = "macos")]
fn request_permissions() {
    use crate::platform::macos::{is_can_screen_recording, is_process_trusted};

    let screen = is_can_screen_recording(true);
    let input = is_process_trusted(true);
    println!("Screen Recording: {}", if screen { "allowed" } else { "not allowed" });
    println!("Accessibility: {}", if input { "allowed" } else { "not allowed" });
    if !(screen && input) {
        // Leave the system prompts up long enough to be answered.
        std::thread::sleep(std::time::Duration::from_secs(120));
    }
}

/// macOS grants Screen Recording per app, and a build that lacks it starts a session that can
/// never produce a frame - the viewer sits on "Logging in..." with nothing to act on. A login
/// error is the only feedback the protocol has before a session exists, so refuse the login and
/// name the permission.
#[cfg(target_os = "macos")]
pub fn screen_capture_error() -> Option<String> {
    if crate::platform::macos::is_can_screen_recording(false) {
        return None;
    }
    Some(format!(
        "{DISPLAY_NAME} is not allowed to record this computer's screen. \
         Open {DISPLAY_NAME} from Applications to be asked again, or turn it on under \
         System Settings > Privacy & Security > Screen & System Audio Recording."
    ))
}

/// Zero third-party requests is a product promise, so the host never probes public STUN servers
/// for its public IPv6 address; it reaches nothing but the rdp.diy servers it was built for.
/// Upstream's local route probe still finds that address when the network has one.
pub fn allow_public_stun() -> bool {
    false
}

/// Restarts the session server (`--server` LaunchAgent) in the caller's login session, so it
/// picks up permissions granted since it started.
#[cfg(target_os = "macos")]
fn restart_agent() {
    let uid = unsafe { hbb_common::libc::getuid() };
    if uid == 0 {
        return;
    }
    let job = format!("gui/{uid}/{}_server", crate::get_full_name());
    match std::process::Command::new("launchctl")
        .args(["kickstart", "-k", &job])
        .status()
    {
        Ok(status) if status.success() => {}
        result => hbb_common::log::warn!("launchctl kickstart {job}: {result:?}"),
    }
}

/// RustDesk's connection manager without its window. The session server relies on this
/// process for file writes and, on Linux, PulseAudio capture.
fn run_headless_cm() {
    use crate::ui_cm_interface::{start_ipc, Client, ConnectionManager, InvokeUiCM};

    #[derive(Clone)]
    struct Headless;
    impl InvokeUiCM for Headless {
        fn add_connection(&self, client: &Client) {
            hbb_common::log::info!("session from {} ({})", client.name, client.peer_id);
        }
        fn remove_connection(&self, _id: i32, _close: bool) {}
        fn new_message(&self, _id: i32, _text: String) {}
        fn change_theme(&self, _dark: String) {}
        fn change_language(&self) {}
        fn show_elevation(&self, _show: bool) {}
        fn update_voice_call_state(&self, _client: &Client) {}
        fn file_transfer_log(&self, _action: &str, _log: &str) {}
    }

    #[cfg(target_os = "linux")]
    std::thread::spawn(crate::ipc::start_pa);
    start_ipc(ConnectionManager { ui_handler: Headless });
}
