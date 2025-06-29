//! Replace Rust's default SipHash 1-3 cryptographic hash function with the
//! non-cryptographic AHash hash function, improving performance by 18%.

use itertools::Itertools;
use tap::{Pipe, Tap};

use ahash::AHashMap;
use std::fmt::{self, Display};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::str::{from_utf8, from_utf8_unchecked};

type StationName = Vec<u8>;
type Temperature = f64;

struct Station {
    count: u64,
    max: Temperature,
    min: Temperature,
    sum: Temperature,
}

impl Station {
    fn new(value: Temperature) -> Self {
        Self {
            count: 1,
            max: value,
            min: value,
            sum: value,
        }
    }

    fn update(&mut self, value: Temperature) {
        self.count += 1;
        self.sum += value;
        self.max = self.max.max(value);
        self.min = self.min.min(value);
    }
}

impl Display for Station {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        const PRECISION: Temperature = 10.0;

        write!(
            f,
            "{:.1}/{:.1}/{:.1}",
            self.min,
            (self.sum * PRECISION / self.count as Temperature).round()
                / PRECISION

                // Add 0.0 to display -0.0 as 0.0, since IEEE 754 rounding
                // produces signed zeros.
                + 0.0,
            self.max
        )
    }
}

pub fn v03_ahash_hash_function(input: &Path) -> String {
    let mut buffer = Vec::<u8>::new();

    let mut file = File::open(input)
        .expect("input file should be readable")
        .pipe(BufReader::new);

    let mut stations: AHashMap<StationName, Station> = AHashMap::new();

    loop {
        let bytes = file
            .read_until(b'\n', &mut buffer)
            .expect("line should be readable");

        if bytes == 0 {
            break;
        }

        // Exclude the trailing newline character (b'\n').
        buffer[..bytes - 1]
            .split_once(|&byte| byte == b';')
            .expect("line should contain exactly one semicolon (';')")
            .pipe(|(station, temperature)| {
                (
                    station,
                    temperature
                        .pipe(|temperature|
                            // SAFETY: The `temperature` must be a valid
                            // `Temperature`, without necessarily being UTF-8
                            // valid.
                            unsafe { from_utf8_unchecked(temperature) })
                        .parse::<Temperature>()
                        .expect("temperature should be a float"),
                )
            })
            .pipe(|(station, temperature)| {
                stations
                    .entry(station.into())
                    .and_modify(|station| station.update(temperature))
                    .or_insert_with(|| Station::new(temperature))
            });

        buffer.clear();
    }

    stations
        .iter()
        .collect::<Vec<_>>()
        .tap_mut(|stations| stations.sort_unstable_by_key(|&(name, _)| name))
        .iter()
        .map(|(name, station)| {
            format!(
                "{}: {}",
                from_utf8(name).expect("station name should be UTF-8 valid"),
                station
            )
        })
        .join(", ")
        .pipe(|output| format!("{{{output}}}"))
}
