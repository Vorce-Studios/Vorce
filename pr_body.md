## Verlinktes Issue

Fixes #370

This PR addresses the issue by fixing a subtle mutable borrow bug in the inspector output module (`output.rs`) related to the NDI Sender Runtime status. The fix guarantees that the `.remove()` operation on `ndi_status_rx` is separated from the immutable borrow scope of `.get()`, successfully implementing the inspector runtime status logic required for the NDI capability gates.
