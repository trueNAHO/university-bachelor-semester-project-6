use clap::{Parser, ValueHint::FilePath};

use std::path::PathBuf;

use iterations::{Iteration, run};

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Iteration to run.
    #[arg(value_enum)]
    iteration: Iteration,

    /// Path to the input file.
    #[arg(
        value_name = "INPUT",
        value_hint = FilePath,
        required = true,
    )]
    input: PathBuf,
}

fn main() {
    let cli = Cli::parse();
    println!("{}", run(cli.iteration, &cli.input));
}
