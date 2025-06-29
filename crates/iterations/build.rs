use itertools::Itertools;
use tap::{Pipe, Tap};

use std::{
    env,
    fs::{self, File},
    io::{self, Write},
    path::Path,
};

const BENCH: &str = "bench";
const INPUT_DIR: &str = "data";
const ITERATIONS: &str = "iterations";
const OUT_DIR: &str = "OUT_DIR";
const SOURCE_DIR: &str = "src/iterations";

macro_rules! writeln_indented {
    ($file:expr, $indent:expr, $($arg:tt)*) => {
        {
            writeln!($file, "{}{}", "    ".repeat($indent), format!($($arg)*))
        }
    };
}

fn file(basename: &str) -> Result<File, io::Error> {
    File::create(
        Path::new(&env::var(OUT_DIR).expect("Rust ensures OUT_DIR is set"))
            .join(format!("{basename}.rs")),
    )
}

fn generate_bench(
    iterations: &Vec<String>,
    mut file: impl Write,
) -> io::Result<()> {
    const GROUP: &str = "benches";

    for iteration in iterations {
        writeln_indented!(
            file,
            0,
            "fn {0}(c: &mut criterion::Criterion) {{",
            iteration
        )?;

        writeln_indented!(
            file,
            1,
            "let input = &std::env::var(\"INPUT\").unwrap_or_else(|_| panic!(\"INPUT pointing to the input file is not set\"));"
        )?;

        writeln_indented!(
            file,
            1,
            "let input = &std::path::Path::new(input);"
        )?;

        writeln_indented!(
            file,
            1,
            "c.bench_function(\"{0}\", |b| b.iter(|| iterations::{0}(input)));",
            iteration
        )?;

        writeln_indented!(file, 0, "}}\n")?;
    }

    writeln_indented!(
        file,
        0,
        "criterion::criterion_group!({}, {});",
        GROUP,
        iterations
            .iter()
            .map(|iteration| iteration.to_string())
            .join(", ")
    )?;

    writeln_indented!(file, 0, "criterion::criterion_main!({});", GROUP)?;

    Ok(())
}

fn generate_iterations(
    iterations: &Vec<String>,
    mut file: impl Write,
) -> io::Result<()> {
    writeln_indented!(file, 0, "#[macro_export]")?;
    writeln_indented!(file, 0, "macro_rules! mod_and_use {{")?;
    writeln_indented!(file, 1, "() => {{")?;

    writeln_indented!(file, 2, "mod iterations {{")?;

    for iteration in iterations {
        writeln_indented!(file, 3, "pub mod {};", iteration)?;
    }

    writeln_indented!(file, 2, "}}\n")?;

    for iteration in iterations {
        writeln_indented!(file, 2, "pub use iterations::{0}::{0};", iteration)?;
    }

    writeln_indented!(file, 1, "}};")?;
    writeln_indented!(file, 0, "}}\n")?;

    writeln_indented!(file, 0, "#[derive(Clone, clap::ValueEnum)]")?;
    writeln_indented!(file, 0, "#[allow(non_camel_case_types)]")?;
    writeln_indented!(file, 0, "pub enum Iteration {{")?;

    for iteration in iterations {
        writeln_indented!(file, 1, "{},", iteration)?;
    }

    writeln_indented!(file, 0, "}}\n")?;

    writeln_indented!(file, 0, "impl std::fmt::Display for Iteration {{")?;

    writeln_indented!(
        file,
        1,
        "fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {{"
    )?;

    writeln_indented!(file, 2, "match self {{")?;

    for iteration in iterations {
        writeln_indented!(
            file,
            3,
            "Iteration::{0} => write!(f, \"{0}\"),",
            iteration
        )?;
    }

    writeln_indented!(file, 2, "}}")?;
    writeln_indented!(file, 1, "}}")?;
    writeln_indented!(file, 0, "}}\n")?;

    writeln_indented!(
        file,
        0,
        "pub fn run(iteration: Iteration, input: &std::path::Path) -> String {{"
    )?;

    writeln_indented!(file, 1, "match iteration {{")?;

    for iteration in iterations {
        writeln_indented!(
            file,
            2,
            "Iteration::{0} => iterations::{0}::{0}(input),",
            iteration
        )?;
    }

    writeln_indented!(file, 1, "}}")?;
    writeln_indented!(file, 0, "}}\n")?;

    writeln_indented!(file, 0, "#[cfg(test)]")?;
    writeln_indented!(file, 0, "mod tests {{")?;

    for (index, (iteration, (input_path, input_name))) in iterations
        .iter()
        .skip(1)
        .cartesian_product(
            fs::read_dir(INPUT_DIR)?
                .map(|entry| {
                    entry
                        .expect("entry should be readable")
                        .path()
                        .tap(|entry| {
                            assert!(entry.is_file(), "entry should be a file")
                        })
                        .pipe(|file| {
                            (
                                file.to_str()
                                    .expect("filename should be valid UTF-8")
                                    .to_string(),
                                file.file_stem()
                                    .expect("filename should have a stem")
                                    .to_str()
                                    .expect(
                                        "filename stem should be valid UTF-8",
                                    )
                                    .to_string(),
                            )
                        })
                })
                .sorted(),
        )
        .enumerate()
    {
        if index != 0 {
            writeln!(file)?;
        }

        writeln_indented!(file, 1, "#[test]")?;
        writeln_indented!(file, 1, "fn {}_{}() {{", iteration, input_name)?;

        writeln_indented!(
            file,
            2,
            "let input = std::path::PathBuf::from(\"{}\");\n",
            input_path
        )?;

        writeln_indented!(file, 2, "assert_eq!(")?;

        writeln_indented!(
            file,
            3,
            "super::iterations::{0}::{0}(&input),",
            iterations
                .first()
                .expect("base implementation should exist"),
        )?;

        writeln_indented!(
            file,
            3,
            "super::iterations::{0}::{0}(&input),",
            iteration,
        )?;

        writeln_indented!(file, 2, ")")?;
        writeln_indented!(file, 1, "}}")?;
    }

    writeln_indented!(file, 0, "}}")?;

    Ok(())
}

fn main() -> io::Result<()> {
    println!("cargo:rerun-if-changed={SOURCE_DIR}");
    println!("cargo:rerun-if-changed={INPUT_DIR}");

    let iterations: Vec<String> = fs::read_dir(SOURCE_DIR)?
        .map(|entry| {
            entry
                .expect("entry should be readable")
                .path()
                .tap(|entry| {
                    assert!(
                        entry.is_file()
                            && entry
                                .extension()
                                .map(|extension| extension == "rs")
                                .unwrap_or(false),
                        "entry should be a Rust file",
                    )
                })
                .pipe(|file| {
                    file.file_stem()
                        .expect("filename should have a stem")
                        .to_str()
                        .expect("filename stem should be valid UTF-8")
                        .to_string()
                })
        })
        .sorted()
        .collect();

    generate_iterations(&iterations, file(ITERATIONS)?)?;
    generate_bench(&iterations, file(BENCH)?)?;

    Ok(())
}
