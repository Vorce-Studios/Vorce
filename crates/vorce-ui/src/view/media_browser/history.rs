use super::state::MediaBrowserState;
use std::path::PathBuf;

pub fn navigate_to(state: &mut MediaBrowserState, path: PathBuf) {
    if path.is_dir() {
        state.current_dir = path.clone();
        state.path_input = path.display().to_string();
        super::scan::refresh_dir(state);
        state.history.truncate(state.history_index + 1);
        state.history.push(path);
        state.history_index = state.history.len() - 1;
    }
}

pub fn navigate_back(state: &mut MediaBrowserState) {
    if state.history_index > 0 {
        state.history_index -= 1;
        state.current_dir = state.history[state.history_index].clone();
        state.path_input = state.current_dir.display().to_string();
        super::scan::refresh_dir(state);
    }
}

pub fn navigate_forward(state: &mut MediaBrowserState) {
    if state.history_index < state.history.len() - 1 {
        state.history_index += 1;
        state.current_dir = state.history[state.history_index].clone();
        state.path_input = state.current_dir.display().to_string();
        super::scan::refresh_dir(state);
    }
}

pub fn navigate_up(state: &mut MediaBrowserState) {
    if let Some(parent) = state.current_dir.parent() {
        navigate_to(state, parent.to_path_buf());
    }
}
