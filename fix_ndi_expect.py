import re

with open("crates/vorce/src/app/actions.rs", "r") as f:
    content = f.read()

# Exact matching to avoid python regex issues.
original = """            UIAction::ConnectNdiSource { part_id, source } => {
                let receiver = app.ndi_receivers.entry(part_id).or_insert_with(|| {
                    info!("Creating new NdiReceiver for part {}", part_id);
                    vorce_io::ndi::NdiReceiver::new().expect("Failed to create NDI receiver")
                });
                info!("Connecting part {} to NDI source '{}'", part_id, source.name);
                if let Err(e) = receiver.connect(&source) {
                    error!("Failed to connect to NDI source: {}", e);
                }
            }"""

replacement = """            UIAction::ConnectNdiSource { part_id, source } => {
                let receiver_result = {
                    if let Some(existing) = app.ndi_receivers.get_mut(&part_id) {
                        Ok(existing)
                    } else {
                        info!("Creating new NdiReceiver for part {}", part_id);
                        match vorce_io::ndi::NdiReceiver::new() {
                            Ok(new_receiver) => {
                                app.ndi_receivers.insert(part_id, new_receiver);
                                Ok(app.ndi_receivers.get_mut(&part_id).unwrap())
                            }
                            Err(e) => Err(e),
                        }
                    }
                };

                match receiver_result {
                    Ok(receiver) => {
                        info!("Connecting part {} to NDI source '{}'", part_id, source.name);
                        if let Err(e) = receiver.connect(&source) {
                            error!("Failed to connect to NDI source: {}", e);
                        }
                    }
                    Err(e) => {
                        error!("Failed to create NDI receiver for part {}: {}", part_id, e);
                    }
                }
            }"""

new_content = content.replace(original, replacement)

with open("crates/vorce/src/app/actions.rs", "w") as f:
    f.write(new_content)
