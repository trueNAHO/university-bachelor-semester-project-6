use clap::{
    Parser,
    ValueHint::{DirPath, FilePath},
};

use tap::Pipe;

use std::{
    fs::File,
    io::BufReader,
    ops::Range,
    path::{Path, PathBuf},
};

use crate::benchmarks::{Benchmarks, Input, Time};

const LINEAR_FILENAME: &str = "linear.svg";
const LOG_FILENAME: &str = "log.svg";

type Error = Box<dyn std::error::Error>;
type XRange = Range<Input>;
type YRange = Range<Time>;

type DataPointsCollection = Vec<DataPoints>;

#[derive(Parser)]
#[command(version, about, long_about = None)]
pub struct Cli {
    /// Base of the logarithmic scale for the x-axis in the log plot.
    #[arg(short, long, value_name = "BASE", default_value = "2")]
    log_base: f64,

    /// Path to the JSON datasets.
    #[arg(
        value_name = "INPUT",
        value_hint = FilePath,
        required = true,
    )]
    input: Vec<PathBuf>,

    /// Directory to write the generated plots to.
    #[arg(
        short,
        long,
        value_name = "DIR",
        default_value = ".",
        value_hint = DirPath
    )]
    output_directory: String,

    /// Minimum value for the x-axis.
    #[arg(long, value_name = "X_MIN")]
    x_min: Option<Input>,

    /// Maximum value for the x-axis.
    #[arg(long, value_name = "X_MAX")]
    x_max: Option<Input>,

    /// Minimum value for the y-axis.
    #[arg(long, value_name = "Y_MIN")]
    y_min: Option<Time>,

    /// Maximum value for the y-axis.
    #[arg(long, value_name = "Y_MAX")]
    y_max: Option<Time>,
}

impl Cli {
    pub fn init() -> Result<
        (DataPointsCollection, XRange, YRange, f64, PathBuf, PathBuf),
        Error,
    > {
        let cli = Cli::parse();

        let data = Self::data(&cli)?;

        let x_range = Self::x_range(&data, cli.x_min, cli.x_max);
        let y_range = Self::y_range(&data, cli.y_min, cli.y_max);

        Ok((
            data,
            x_range,
            y_range,
            cli.log_base,
            Path::new(&cli.output_directory).join(LINEAR_FILENAME),
            Path::new(&cli.output_directory).join(LOG_FILENAME),
        ))
    }

    fn data(cli: &Cli) -> Result<DataPointsCollection, Error> {
        cli.input
            .iter()
            .map(|path| -> Result<DataPoints, Error> {
                let entries = serde_json::from_reader::<_, Benchmarks>(
                    BufReader::new(File::open(path)?),
                )?;

                Ok(DataPoints {
                    data: entries
                        .benchmarks
                        .iter()
                        .map(|benchmark| {
                            const NANOSECONDS_PER_SECOND: f64 = 1e9;

                            (
                                benchmark.input,
                                benchmark.time / NANOSECONDS_PER_SECOND,
                            )
                        })
                        .collect(),

                    source: entries.name,
                })
            })
            .collect::<Result<Vec<_>, _>>()
    }

    fn x_range(
        data: &DataPointsCollection,
        x_min: Option<Input>,
        x_max: Option<Input>,
    ) -> XRange {
        data.iter()
            .flat_map(|s| s.data.iter().map(|(x, _)| *x))
            .pipe(|x| {
                x_min.unwrap_or(
                    x.clone()
                        .min()
                        .expect("at least one input entry should exist"),
                )
                    ..x_max.unwrap_or(
                        x.clone()
                            .max()
                            .expect("at least one input entry should exist"),
                    )
            })
    }

    fn y_range(
        data: &DataPointsCollection,
        y_min: Option<Time>,
        y_max: Option<Time>,
    ) -> YRange {
        data.iter()
            .flat_map(|s| s.data.iter().map(|(_, y)| *y))
            .pipe(|y| {
                y_min.unwrap_or(
                    y.clone()
                        .min_by(|a, b| {
                            a.partial_cmp(b).expect("time should be comparable")
                        })
                        .expect("at least one time entry should exist"),
                )
                    ..y_max.unwrap_or(
                        y.max_by(|a, b| {
                            a.partial_cmp(b).expect("time should be comparable")
                        })
                        .expect("at least one time entry should exist"),
                    )
            })
    }
}

pub struct DataPoints {
    pub data: Vec<(Input, Time)>,
    pub source: String,
}
