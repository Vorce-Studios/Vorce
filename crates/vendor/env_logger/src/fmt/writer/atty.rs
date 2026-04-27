/*
This internal module contains the terminal detection implementation using std::io::IsTerminal.
*/

use std::io::{IsTerminal, stderr, stdout};

mod imp {
    pub(in crate::fmt) fn is_stdout() -> bool {
        stdout().is_terminal()
    }

    pub(in crate::fmt) fn is_stderr() -> bool {
        stderr().is_terminal()
    }
}

pub(in crate::fmt) use self::imp::*;
