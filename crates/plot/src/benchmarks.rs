use serde::Deserialize;

pub type Input = i64;
pub type Time = f64;

#[derive(Deserialize)]
pub struct Benchmark {
    pub input: Input,
    pub time: Time,
}

#[derive(Deserialize)]
pub struct Benchmarks {
    pub benchmarks: Vec<Benchmark>,
    pub name: String,
}
