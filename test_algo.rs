use std::time::Instant;

fn main() {
    let response_text = (0..50000).map(|_| "a").collect::<String>() + "\"error\"" + &((0..5000).map(|_| "a").collect::<String>());

    let start = Instant::now();
    for _ in 0..10000 {
        let _ = response_text.contains("\"error\"");
    }
    println!("Baseline contains loop: {:?}", start.elapsed());

    // Alternative? Not a loop in the code! The problem description is:
    // "Inefficient `.contains()` inside a loop"
    // "Converting the slice/Vec to a HashSet before the loop requires a small refactor but provides significant algorithmic improvement."
}
