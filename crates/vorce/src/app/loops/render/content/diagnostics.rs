use crate::app::core::app_struct::RuntimeRenderQueueItem;
use std::collections::HashMap;
use std::time::Instant;

use crate::app::loops::render::logging::{clear_video_issue, should_log_video_issue};

pub(crate) fn process_diagnostics(
    target_ops: &[RuntimeRenderQueueItem],
    video_log_times: &mut HashMap<String, Instant>,
    real_output_id: u64,
    is_preview_output: bool,
    output_id: u64,
) {
    for item in target_ops {
        for diag in &item.diagnostics {
            let issue_key = format!("{}:{}:{}", diag.code, diag.module_id, diag.part_id);
            if should_log_video_issue(video_log_times, issue_key) {
                match diag.severity {
                    crate::app::core::app_struct::DiagnosticSeverity::Warning => {
                        tracing::warn!(
                            "Fehler in Videoausgabe: Modul {} / Part {} - {}",
                            diag.module_id,
                            diag.part_id,
                            diag.message
                        );
                    }
                    crate::app::core::app_struct::DiagnosticSeverity::Error => {
                        tracing::error!(
                            "Fehler in Videoausgabe: Modul {} / Part {} - {}",
                            diag.module_id,
                            diag.part_id,
                            diag.message
                        );
                    }
                }
            }
        }
    }

    let empty_ops_issue_key = format!(
        "video-output-empty-ops:{real_output_id}:{}",
        if is_preview_output { "preview" } else { "output" }
    );
    if target_ops.is_empty() {
        if output_id != 0 && should_log_video_issue(video_log_times, empty_ops_issue_key.clone()) {
            tracing::warn!(
                "Fehler in Videoausgabe: {} {} bleibt leer, weil keine RenderOps fuer diesen Output erzeugt wurden.",
                if is_preview_output {
                    "Output-Preview"
                } else {
                    "Output"
                },
                real_output_id
            );
        }
    } else {
        clear_video_issue(video_log_times, empty_ops_issue_key);
    }
}
