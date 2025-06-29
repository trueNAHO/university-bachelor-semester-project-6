//! Sequentially read and parse measurement lines, mapping station names to
//! their minimum, maximum, sum, and count in a hash map, then sorting by
//! station name before computing and formatting the final output.

use itertools::Itertools;
use tap::{Pipe, Tap};

use std::collections::HashMap;
use std::fmt::{self, Display};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

type StationName = String;
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

pub fn v01_base(input: &Path) -> String {
    let mut stations: HashMap<StationName, Station> = HashMap::new();

    File::open(input)
        .expect("input file should be readable")
        .pipe(BufReader::new)
        .lines()
        .for_each(|line| {
            line.expect("line should be readable")
                .split_once(";")
                .expect("line should contain exactly one semicolon (';')")
                .pipe(|(station, temperature)| {
                    (
                        station,
                        temperature
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
        });

    stations
        .iter()
        .collect::<Vec<_>>()
        .tap_mut(|stations| stations.sort_unstable_by_key(|&(name, _)| name))
        .iter()
        .map(|(name, station)| format!("{name}: {station}"))
        .join(", ")
        .pipe(|output| format!("{{{output}}}"))
}
