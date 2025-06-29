mod benchmarks;
mod cli;
mod plot;

use cli::Cli;
use plot::plot;
use plotters::prelude::IntoLogRange;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let (data, x_range, y_range, log_base, linear_path, log_path) =
        Cli::init()?;

    plot(&data, x_range.clone(), y_range.clone(), &linear_path)?;

    plot(
        &data,
        x_range.log_scale().base(log_base),
        y_range,
        &log_path,
    )?;

    Ok(())
}
