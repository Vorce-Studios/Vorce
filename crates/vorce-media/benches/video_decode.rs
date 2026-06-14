use criterion::{criterion_group, criterion_main, Criterion};
use std::hint::black_box;
use vorce_media::{TestPatternDecoder, VideoDecoder};

fn bench_video_decode(c: &mut Criterion) {
    c.benchmark_group("video_decode").bench_function("decode_frame_1080p", |b| {
        let mut decoder = TestPatternDecoder::new(1920, 1080, std::time::Duration::from_secs(60), 30.0);

        b.iter(|| {
            let frame = decoder.next_frame().unwrap();
            black_box(frame);
        });
    });
}

criterion_group!(benches, bench_video_decode);
criterion_main!(benches);
