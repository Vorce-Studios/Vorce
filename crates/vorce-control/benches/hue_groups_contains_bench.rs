use std::hint::black_box;
use criterion::{ criterion_group, criterion_main, Criterion};

fn benchmark_contains_error(c: &mut Criterion) {
    // Generate a long response text.
    let response_text = (0..5000).map(|_| "a").collect::<String>()
        + "\"error\""
        + &((0..5000).map(|_| "a").collect::<String>());

    c.bench_function("string_contains", |b| {
        b.iter(|| {
            let res = black_box(&response_text).contains(black_box("\"error\""));
            black_box(res);
        })
    });
}

criterion_group!(benches, benchmark_contains_error);
criterion_main!(benches);
