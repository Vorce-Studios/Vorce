//! UI view module.

pub mod dashboard;
pub mod media_browser;
pub mod media_manager_wrapper;
pub mod menu_bar;
pub mod module_sidebar;

pub use dashboard::*;
pub use media_browser::{
    format_duration, format_size, MediaBrowser, MediaBrowserAction, MediaEntry, MediaFolders,
    MediaType, SortMode, ThumbnailHandle, ViewMode,
};
pub use media_manager_wrapper::*;
pub use menu_bar::*;
pub use module_sidebar::*;
