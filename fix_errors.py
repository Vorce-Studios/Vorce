with open("crates/vorce-ui/src/core/config/io.rs", "r") as f:
    text = f.read()

text = text.replace("pub(crate) pub(crate)", "pub(crate)")

with open("crates/vorce-ui/src/core/config/io.rs", "w") as f:
    f.write(text)
