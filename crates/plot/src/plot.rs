use plotters::{
    chart::ChartBuilder,
    coord::ranged1d::{AsRangedCoord, ValueFormatter},
    prelude::{IntoDrawingArea, PathElement, SVGBackend},
    series::LineSeries,
    style::{BLACK, Color, HSLColor, RGBColor, WHITE},
};

use tap::{Pipe, Tap};

use std::path::Path;

use crate::{
    benchmarks::{Input, Time},
    cli::DataPoints,
};

const BACKGROUND_COLOR: RGBColor = WHITE;
const BACKGROUND_OPACITY: f64 = 0.8;
const BORDER_COLOR: RGBColor = BLACK;
const HSL_LIGHTNESS: f64 = 0.5;
const HSL_SATURATION: f64 = 1.0;
const LEGEND_LINE_LENGTH: i32 = 20;
const OUTPUT_SIZE: (u32, u32) = (1000, 1000);
const X_DESC: &str = "Rows";
const X_LABEL_AREA_SIZE: u32 = 30;
const Y_DESC: &str = "Time (s)";
const Y_LABEL_AREA_SIZE: u32 = 30;

pub fn plot<X, Y>(
    data: &[DataPoints],
    x_range: X,
    y_range: Y,
    filename: &Path,
) -> Result<(), Box<dyn std::error::Error>>
where
    X: AsRangedCoord<Value = Input>,
    Y: AsRangedCoord<Value = Time>,
    X::CoordDescType: ValueFormatter<Input>,
    Y::CoordDescType: ValueFormatter<Time>,
{
    let mut chart = SVGBackend::new(&filename, OUTPUT_SIZE)
        .into_drawing_area()
        .tap(|area| {
            area.fill(&BACKGROUND_COLOR)
                .expect("drawing area should be fillable")
        })
        .pipe_ref(ChartBuilder::on)
        .x_label_area_size(X_LABEL_AREA_SIZE)
        .y_label_area_size(Y_LABEL_AREA_SIZE)
        .build_cartesian_2d(x_range, y_range)?;

    chart
        .configure_mesh()
        .x_desc(X_DESC)
        .y_desc(Y_DESC)
        .draw()?;

    let series_count = data.len();

    for (index, series) in data.iter().enumerate() {
        let color = HSLColor(
            index as f64 / series_count as f64,
            HSL_SATURATION,
            HSL_LIGHTNESS,
        );

        chart
            .draw_series(LineSeries::new(series.data.clone(), color))?
            .label(series.source.clone())
            .legend(move |(x, y)| {
                PathElement::new(
                    vec![(x, y), (x + LEGEND_LINE_LENGTH, y)],
                    color,
                )
            });
    }

    chart
        .configure_series_labels()
        .background_style(BACKGROUND_COLOR.mix(BACKGROUND_OPACITY))
        .border_style(BORDER_COLOR)
        .draw()?;

    println!("Saved plot: {}", filename.display());

    Ok(())
}
