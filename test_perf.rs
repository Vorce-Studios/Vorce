use std::time::Instant;

fn main() {
    let mut vec_strings = vec![];
    for i in 0..1000 {
        vec_strings.push(format!("response_{}", i));
    }
    vec_strings.push("\"error\"".to_string());

    // Simulate the function doing substring matching over response body.
    let response_text = (0..5000).map(|_| "a").collect::<String>() + "\"error\"" + &((0..5000).map(|_| "a").collect::<String>());

    let start = Instant::now();
    for _ in 0..10000 {
        let _ = response_text.contains("\"error\"");
    }
    println!("Baseline contains loop: {:?}", start.elapsed());
}
