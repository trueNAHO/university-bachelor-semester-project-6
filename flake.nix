{
  description = "University: Bachelor Semester Project 6 (2025/02/17--2025/07/04)";

  inputs = {
    "1brc" = {
      flake = false;
      url = "github:gunnarmorling/1brc";
    };

    advisory-db = {
      flake = false;
      url = "github:rustsec/advisory-db";
    };

    crane.url = "github:ipetkov/crane";

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils = {
      inputs.systems.follows = "systems";
      url = "github:numtide/flake-utils";
    };

    git-hooks = {
      inputs = {
        flake-compat.follows = "";
        nixpkgs.follows = "nixpkgs";
      };

      url = "github:cachix/git-hooks.nix";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystem (
      system: let
        inherit (pkgs) lib;

        crane = lib.fix (
          self: {
            args = {
              inherit (self) src;

              buildInputs = lib.optionals pkgs.stdenv.isDarwin [pkgs.libiconv];
              strictDeps = true;
            };

            buildPackage = args:
              self.lib.buildPackage (
                self.args
                // {
                  inherit
                    (self.lib.crateNameFromCargoToml {inherit (self) src;})
                    version
                    ;

                  inherit (self) cargoArtifacts;

                  doCheck = false;
                }
                // lib.throwIf
                (args ? buildInputs || args ? nativeBuildInputs)
                "declare buildInputs and nativeBuildInputs within crane.args for crane.cargoArtifacts to incorporate them"
                args
              );

            cargoArtifacts = self.lib.buildDepsOnly self.args;
            lib = (inputs.crane.mkLib pkgs).overrideToolchain fenix;
            src = self.lib.cleanCargoSource ./.;

            workspace.src = workspaces:
              lib.fileset.toSource {
                fileset = lib.fileset.unions (
                  workspaces ++ [./Cargo.lock ./Cargo.toml]
                );

                root = ./.;
              };
          }
        );

        fenix = inputs.fenix.packages.${system}.default.withComponents [
          "cargo"
          "clippy"
          "rustc"
          "rustfmt"
        ];

        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in
        builtins.mapAttrs
        (
          name: output:
            if name == "formatter"
            then output
            else
              builtins.mapAttrs
              (
                _: value:
                  value
                  // {
                    meta =
                      value.meta or {}
                      // {
                        license = value.meta.license or lib.licenses.mit;

                        maintainers = lib.unique (
                          [lib.maintainers.naho] ++ value.meta.maintainers or []
                        );
                      };
                  }
              )
              output
        )
        {
          checks =
            lib.attrsets.unionOfDisjoint
            inputs.self.packages.${system}
            {
              cargo-audit = crane.lib.cargoAudit {
                inherit (crane) src;
                inherit (inputs) advisory-db;
              };

              cargo-clippy = crane.lib.cargoClippy (
                crane.args
                // {
                  inherit (crane) cargoArtifacts;

                  cargoClippyExtraArgs = "--all-targets -- ${
                    lib.cli.toGNUCommandLineShell {} {
                      deny = ["clippy::unwrap_used" "warnings"];
                    }
                  }";
                }
              );

              cargo-deny = crane.lib.cargoDeny {inherit (crane) src;};
              cargo-fmt = crane.lib.cargoFmt {inherit (crane) src;};

              cargo-nextest = crane.lib.cargoNextest (
                crane.args
                // {
                  inherit (crane) cargoArtifacts;

                  cargoNextestPartitionsExtraArgs = "--no-tests=pass";

                  src = pkgs.buildEnv {
                    name = "cargo-nextest-src";

                    paths = [
                      (
                        pkgs.buildEnv {
                          extraPrefix = "/crates/iterations/data";
                          name = "cargo-nextest-src-data";
                          paths = [crates/iterations/data];
                        }
                      )

                      crane.args.src
                    ];
                  };
                }
              );

              cargo-test-doc = crane.lib.cargoDocTest (
                crane.args // {inherit (crane) cargoArtifacts;}
              );

              directory-file-count-consistency = let
                directories = [
                  ./benchmarks
                  inputs.self.packages.${system}.descriptions
                  inputs.self.packages.${system}.diffs
                ];
              in
                lib.throwIfNot
                (
                  let
                    lengths =
                      map
                      (
                        directory:
                          builtins.length (
                            builtins.attrNames (builtins.readDir directory)
                          )
                      )
                      directories;
                  in
                    builtins.all
                    (
                      let
                        first = builtins.head lengths;
                      in
                        output: output == first
                    )
                    (builtins.tail lengths)
                )
                "inconsistent file count in directories: ${
                  builtins.concatStringsSep ", " directories
                }"
                pkgs.emptyDirectory;

              git-hooks = inputs.git-hooks.lib.${system}.run {
                hooks = {
                  alejandra = {
                    enable = true;
                    settings.verbosity = "quiet";
                  };

                  deadnix.enable = true;
                  statix.enable = true;

                  typos = {
                    enable = true;
                    settings.exclude = "crates/iterations/data/*.txt";
                  };

                  yamllint.enable = true;
                };

                src = ./.;
              };

              taplo-fmt = crane.lib.taploFmt {
                src = lib.sources.sourceFilesBySuffices crane.src [".toml"];
              };
            };

          devShells.default = crane.lib.devShell {
            inherit (inputs.self.checks.${system}.git-hooks) shellHook;

            checks = inputs.self.checks.${system};
            inputsFrom = [inputs.self.packages.${system}];

            packages = [
              inputs.self.checks.${system}.git-hooks.enabledPackages
              pkgs.cargo-criterion
            ];
          };

          formatter = pkgs.alejandra;

          packages = let
            inputs' = let
              attrName = size: "input-${toString size}";
              attrValue = size: "${attrName size}.txt";

              description = size: "Dataset with ${toString size} row${
                lib.optionalString (size != 1) "s"
              }";

              maxInput = let
                size = maxInputSize;
              in
                pkgs.runCommand
                (attrName size)
                {
                  meta.description = description size;
                  nativeBuildInputs = [pkgs.jdk21_headless];
                }
                ''
                  mkdir --parents $out

                  java \
                    ${inputs."1brc"}/src/main/java/dev/morling/onebrc/CreateMeasurements.java \
                    ${toString size}

                  mv measurements.txt $out/${attrValue size}
                '';

              maxInputSize = 1000000000;
            in
              builtins.foldl'
              (
                acc: size: let
                  input = attrName size;
                in
                  acc
                  // {
                    ${input} =
                      pkgs.runCommand
                      input
                      {meta.description = description size;}
                      ''
                        mkdir --parents $out

                        head \
                          --lines ${toString size} \
                          ${maxInput}/${attrValue maxInputSize} \
                          >$out/${attrValue size}
                      '';
                  }
              )
              {${attrName maxInputSize} = maxInput;}
              (
                let
                  base = 2;
                  linearsteps = 100;
                in
                  lib.remove maxInputSize (
                    map
                    (builtins.mul (maxInputSize / linearsteps))
                    (lib.range 1 linearsteps)
                    ++ (
                      let
                        log = base: value:
                          lib.fix
                          (
                            self: value: power:
                              if value >= base
                              then self (value / base) (power + 1)
                              else power
                          )
                          (value + 0.0)
                          0;

                        pow = lib.fix (
                          self: base: power:
                            if power != 0
                            then base * (self base (power - 1))
                            else 1
                        );
                      in
                        map
                        (pow base)
                        (lib.range 0 (log base maxInputSize))
                    )
                  )
              );

            workspace =
              builtins.foldl'
              (
                acc: package:
                  acc
                  // {
                    ${package} = let
                      path = lib.path.append ./crates package;
                    in
                      crane.buildPackage {
                        cargoExtraArgs = "--package ${package}";

                        meta = {
                          inherit
                            ((lib.importTOML ./Cargo.toml).workspace.package)
                            homepage
                            ;

                          inherit
                            (
                              (
                                lib.importTOML (
                                  lib.path.append path "Cargo.toml"
                                )
                              ).package
                            )
                            description
                            ;

                          mainProgram = package;
                        };

                        src = crane.workspace.src [path];
                      };
                  }
              )
              {}
              (builtins.attrNames (builtins.readDir ./crates));
          in
            lib.fix (
              self:
                builtins.foldl' lib.attrsets.unionOfDisjoint {} [
                  inputs'
                  workspace

                  {
                    benchmark = pkgs.writeShellApplication {
                      meta.description = "Benchmarking tool for iterations against inputs";
                      name = "benchmark";

                      runtimeInputs = [
                        (
                          pkgs.inxi.override {
                            withRecommendedSystemPrograms = true;
                          }
                        )

                        fenix
                        pkgs.auto-cpufreq
                        pkgs.cargo-criterion
                        pkgs.coreutils
                        pkgs.diffutils
                        pkgs.findutils
                        pkgs.gawk
                        pkgs.gcc
                        pkgs.gitMinimal
                        pkgs.gnused
                        pkgs.jq
                        pkgs.systemdMinimal
                      ];

                      text = let
                        inputs'' =
                          lib.concatMapStringsSep
                          "\n    "
                          (
                            input: "[${
                              lib.removePrefix "input-" input.name
                            }]=${input}/${
                              let
                                files = builtins.attrNames (
                                  builtins.readDir input
                                );

                                length = builtins.length files;
                              in
                                lib.throwIfNot
                                (length == 1)
                                "expected one file inside ${input}, but got: ${length}"
                                (builtins.head files)
                            }"
                          )
                          (
                            builtins.sort
                            (
                              a: b:
                                builtins.head (lib.naturalSort [a.name b.name])
                                == a.name
                            )
                            (builtins.attrValues inputs')
                          );

                        iterations = builtins.concatStringsSep "\n    " (
                          lib.naturalSort (
                            map (lib.removeSuffix ".rs") (
                              builtins.attrNames (
                                builtins.readDir crates/iterations/src/iterations
                              )
                            )
                          )
                        );
                      in ''
                        check_current_working_directory() {
                          git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
                            return

                          git ls-files | while read -r file; do
                            diff --brief "${inputs.self}/$file" "$file" || return
                          done
                        }

                        filter_benchmarks() {
                          printf 'iteration filter: %s\n' "$iteration_filter"
                          printf 'input filter: %s\n' "$input_filter"

                          for input in "''${!inputs[@]}"; do
                            if ! [[ "$input" =~ $input_filter ]]; then
                              unset 'inputs[$input]'
                            fi
                          done

                          for iteration in "''${!iterations[@]}"; do
                            if
                              ! [[
                                "''${iterations[$iteration]}" =~ $iteration_filter
                              ]];
                            then
                              unset 'iterations[$iteration]'
                            fi
                          done

                          printf \
                            'selected %s: %s\n' \
                            iterations \
                            "$(
                              printf '%s, ' "''${iterations[@]}" | sed 's/, $//'
                            )" \
                            inputs \
                            "$(
                              printf '%s\n' "''${!inputs[@]}" |
                                sort --general-numeric-sort |
                                xargs printf '%s, ' |
                                sed 's/, $//'
                            )"
                        }

                        get_metadata() {
                          local inxi_json_cache

                          inxi_json_cache="$(
                            inxi \
                              --admin \
                              --cpu \
                              --disk \
                              --graphics \
                              --memory \
                              --output json \
                              --output-file print \
                              --partitions \
                              --system |
                              jq '
                                walk(
                                  if type == "object" then
                                    with_entries(
                                      .key |= (
                                        capture(
                                          "^[0-9]+#[0-9]+#[0-9]+#(?<key>.*)"
                                        ).key // .
                                      )
                                    )

                                  else
                                    .
                                  end
                                ) |
                                add
                              '
                          )"

                          inxi_access_first() {
                            inxi_select_first "$1" ".\"$2\" != null" "$2"
                          }

                          inxi_select_first() {
                            inxi_query "[.\"$1\"[] | select($2)][0] | .\"$3\""
                          }

                          inxi_query() {
                            jq --raw-output "$1" <<<"$inxi_json_cache"
                          }

                          commit="$(git rev-parse HEAD)"

                          software_rust_cargo_version="$(cargo --version)"
                          software_rust_rustc_version="$(rustc --version)"

                          hardware_architecture="$(inxi_access_first System arch)"

                          hardware_cpu_cores="$(inxi_access_first CPU cores)"
                          hardware_cpu_name="$(inxi_access_first CPU model)"
                          hardware_cpu_threads="$(inxi_access_first CPU threads)"

                          hardware_gpu_name="$(
                            inxi_select_first \
                              Graphics \
                              "
                                .Device != null and
                                .driver != null and
                                .type != \"USB\"
                              " \
                              Device
                          )"

                          hardware_ram_name="$(inxi_access_first Memory part-no)"
                          hardware_ram_size="$(inxi_access_first Memory total)"
                          hardware_ram_speed="$(inxi_access_first Memory speed)"
                          hardware_ram_type="$(inxi_access_first Memory type)"

                          hardware_storage_name="$(
                            inxi_access_first Drives model
                          )"

                          hardware_storage_size="$(
                            inxi_select_first Partition ".ID == \"/\"" raw-size
                          )"

                          hardware_storage_speed="$(
                            inxi_access_first Drives speed
                          )"

                          software_filesystem="$(
                            inxi_select_first Partition ".ID == \"/\"" fs
                          )"

                          software_kernel_name="$(uname --kernel-name)"

                          software_kernel_version="$(
                            inxi_access_first System Kernel
                          )"

                          software_os_name="$(
                            inxi_access_first System Distro | awk '{ print $1 }'
                          )"

                          software_os_version="$(
                            inxi_access_first System Distro | awk '{ print $2 }'
                          )"

                          unset -f inxi_access_first inxi_query inxi_select_first
                        }

                        run_benchmarks() {
                          local total_inputs=''${#inputs[@]}
                          local total_iterations=''${#iterations[@]}

                          mkdir --parents benchmarks

                          for iteration in "''${!iterations[@]}"; do
                            local input_index=1

                            for input in $(
                              printf '%s\n' "''${!inputs[@]}" |
                                sort --general-numeric-sort
                            ); do
                              printf \
                                '[%d/%d][%d/%d] %s %s\n' \
                                "$((iteration + 1))" \
                                "$total_iterations" \
                                "$input_index" \
                                "$total_inputs" \
                                "''${iterations[$iteration]}" \
                                "''${inputs[$input]}" \
                                >&2

                              INPUT="''${inputs[$input]}" \
                                cargo criterion \
                                  --message-format json \
                                  -- \
                                  "''${iterations[$iteration]}" |
                                  jq "
                                    select(.reason == \"benchmark-complete\") |
                                    {
                                      input: $input,
                                      time: .mean.estimate
                                    }
                                  "

                              ((++input_index))
                            done |
                              jq \
                                --slurp \
                                --arg iteration_name "''${iterations[$iteration]}" \
                                --arg metadata_commit "$commit" \
                                --arg metadata_hardware_architecture "$hardware_architecture" \
                                --arg metadata_hardware_cpu_cores "$hardware_cpu_cores" \
                                --arg metadata_hardware_cpu_name "$hardware_cpu_name" \
                                --arg metadata_hardware_cpu_threads "$hardware_cpu_threads" \
                                --arg metadata_hardware_gpu_name "$hardware_gpu_name" \
                                --arg metadata_hardware_ram_name "$hardware_ram_name" \
                                --arg metadata_hardware_ram_size "$hardware_ram_size" \
                                --arg metadata_hardware_ram_speed "$hardware_ram_speed" \
                                --arg metadata_hardware_ram_type "$hardware_ram_type" \
                                --arg metadata_hardware_storage_name "$hardware_storage_name" \
                                --arg metadata_hardware_storage_size "$hardware_storage_size" \
                                --arg metadata_hardware_storage_speed "$hardware_storage_speed" \
                                --arg metadata_software_filesystem "$software_filesystem" \
                                --arg metadata_software_kernel_name "$software_kernel_name" \
                                --arg metadata_software_kernel_version "$software_kernel_version" \
                                --arg metadata_software_os_name "$software_os_name" \
                                --arg metadata_software_os_version "$software_os_version" \
                                --arg metadata_software_rust_cargo_version "$software_rust_cargo_version" \
                                --arg metadata_software_rust_rustc_version "$software_rust_rustc_version" \
                                '
                                  {
                                    benchmarks: .,

                                    metadata: {
                                      commit: $metadata_commit,

                                      hardware: {
                                        architecture:
                                          $metadata_hardware_architecture,

                                        cpu: {
                                          cores: (
                                            $metadata_hardware_cpu_cores |
                                              tonumber
                                          ),

                                          name: $metadata_hardware_cpu_name,

                                          threads: (
                                            $metadata_hardware_cpu_threads |
                                              tonumber
                                          )
                                        },

                                        gpu: {
                                          name: $metadata_hardware_gpu_name
                                        },

                                        ram: {
                                          frequency:
                                            $metadata_hardware_ram_speed,

                                          name: $metadata_hardware_ram_name,
                                          size: $metadata_hardware_ram_size,
                                          type: $metadata_hardware_ram_type
                                        },

                                        storage: {
                                          name: $metadata_hardware_storage_name,
                                          size: $metadata_hardware_storage_size
                                        }
                                      },

                                      software: {
                                        filesystem: $metadata_software_filesystem,

                                        kernel: {
                                          name: $metadata_software_kernel_name,

                                          version:
                                            $metadata_software_kernel_version
                                        },

                                        os: {
                                          name: $metadata_software_os_name,
                                          version: $metadata_software_os_version
                                        },

                                        rust: {
                                          cargo:
                                            $metadata_software_rust_cargo_version,

                                          rustc:
                                            $metadata_software_rust_rustc_version
                                        }
                                      }
                                    },

                                    name: $iteration_name
                                  }
                                ' \
                                >"benchmarks/''${iterations[$iteration]}.json"
                          done
                        }

                        stabilize_system() {
                          local -r target_governor=performance

                          # For simplicity, only auto-cpufreq is supported.
                          if ! systemctl is-active --quiet auto-cpufreq; then
                            return 1
                          fi

                          original_governor="$(
                            auto-cpufreq --get-state | sed 's/^default$/reset/'
                          )"

                          if [[
                            "$original_governor" != "$target_governor"
                          ]]; then
                            sudo auto-cpufreq --force "$target_governor" ||
                              return 2

                            trap \
                              'sudo auto-cpufreq --force "$original_governor"' \
                              EXIT
                          fi
                        }

                        main() {
                          local input_filter="^(''${2:-.*})$"
                          local iteration_filter="''${1:-.*}"

                          if ! check_current_working_directory; then
                            printf \
                              'Current directory (%s) does not match expected Nix source tree: %s\n' \
                              "$PWD" \
                              ${inputs.self} \
                              >&2

                            exit 1
                          fi

                          declare -A inputs=(
                            ${inputs''}
                          )

                          local iterations=(
                            ${iterations}
                          )

                          filter_benchmarks
                          stabilize_system || :
                          get_metadata
                          run_benchmarks
                        }

                        main "$@"
                      '';
                    };

                    benchmark-metadata = pkgs.stdenvNoCC.mkDerivation {
                      dontUnpack = true;

                      installPhase = ''
                        mkdir $out
                        jq . $src >$out/metadata.json
                      '';

                      meta.description = "Benchmark metadata";
                      name = "metadata";
                      nativeBuildInputs = [pkgs.jq];

                      src = let
                        benchmarks = builtins.attrNames (
                          builtins.readDir directory
                        );

                        directory = ./benchmarks;
                        first = getMetadata (builtins.head benchmarks);

                        getMetadata = benchmark:
                          builtins.removeAttrs
                          (
                            builtins.fromJSON (
                              builtins.readFile (
                                lib.path.append directory benchmark
                              )
                            )
                          ).metadata
                          ["commit"];
                      in
                        lib.throwIfNot
                        (
                          builtins.all
                          (metadata: metadata == first)
                          (map getMetadata (builtins.tail benchmarks))
                        )
                        "benchmark metadata mismatch: ${directory}"
                        (builtins.toFile "metadata" (builtins.toJSON first));
                    };

                    default = pkgs.buildEnv {
                      meta.description = "Bundle of the benchmark, benchmark-metadata, descriptions, diffs, docs, inputs, plots, and workspace packages";
                      name = "default";

                      paths =
                        (with self; [benchmark workspace docs])
                        ++ map
                        (
                          package:
                            pkgs.buildEnv {
                              extraPrefix = "/share/iterations/${package}";
                              name = "inputs-share-iterations-${package}";
                              paths = [self.${package}];
                            }
                        ) ["benchmark-metadata" "descriptions" "diffs" "inputs" "plots"];
                    };

                    descriptions =
                      lib.recursiveUpdate
                      (
                        pkgs.linkFarmFromDrvs "descriptions" (
                          map
                          (
                            iteration:
                              pkgs.runCommand
                              "${lib.removeSuffix ".rs" iteration}.md"
                              {nativeBuildInputs = [pkgs.gawk];}
                              ''
                                awk '
                                  ! /^\/\/!/ { exit }
                                  { print gensub(/^\/\/! ?/, "", 1) }
                                ' ${
                                  lib.escapeShellArg
                                  "${crates/iterations/src/iterations}/${iteration}"
                                } >$out
                              ''
                          )
                          (
                            builtins.attrNames (
                              builtins.readDir crates/iterations/src/iterations
                            )
                          )
                        )
                      )
                      {
                        meta.description = "Module documentations of the iterations implementations";
                      };

                    diffs =
                      lib.recursiveUpdate
                      (
                        pkgs.linkFarmFromDrvs "diffs" (
                          map
                          (
                            iteration:
                              pkgs.runCommand
                              "${
                                iteration.previous.name
                              }-${
                                iteration.current.name
                              }.diff"
                              {nativeBuildInputs = [pkgs.diffutils];}
                              ''
                                diff \
                                  --unified \
                                  --label ${iteration.previous.arg} \
                                  --label ${iteration.current.arg} \
                                  ${iteration.previous.path} \
                                  ${iteration.current.path} \
                                  >$out || status="$?"

                                if ((status != 1)); then
                                  exit "$((status + 1))"
                                fi
                              ''
                          )
                          (
                            let
                              base = toString /dev/null;

                              crates =
                                [base]
                                ++ builtins.attrNames (
                                  builtins.readDir crates/iterations/src/iterations
                                );
                            in
                              builtins.concatMap
                              (
                                index:
                                  lib.singleton (
                                    builtins.mapAttrs
                                    (
                                      _: index: let
                                        crate = builtins.elemAt crates index;
                                      in {
                                        arg = lib.escapeShellArg crate;

                                        name = lib.removePrefix "/" (
                                          lib.removeSuffix ".rs" crate
                                        );

                                        path =
                                          if crate == base
                                          then base
                                          else
                                            (
                                              let
                                                file = lib.escapeShellArg "${
                                                  crates/iterations/src/iterations
                                                }/${crate}";
                                              in
                                                pkgs.runCommand
                                                "body-${crate}"
                                                {
                                                  nativeBuildInputs = [
                                                    pkgs.gawk
                                                  ];
                                                }
                                                ''
                                                  awk \
                                                    '
                                                      BEGIN { body = 0 }

                                                      ! /^\/\/!|^[[:space:]]*$/ {
                                                        body = 1
                                                      }

                                                      body { print }
                                                    ' \
                                                    ${file} \
                                                    >$out
                                                ''
                                            );
                                      }
                                    )
                                    {
                                      current = index + 1;
                                      previous = index;
                                    }
                                  )
                              )
                              (lib.range 0 (builtins.length crates - 2))
                          )
                        )
                      )
                      {
                        meta.description = "diff between consecutive iteration implementations";
                      };

                    docs = crane.lib.cargoDoc (
                      crane.args // {inherit (crane) cargoArtifacts;}
                    );

                    inputs = pkgs.buildEnv {
                      meta.description = "Bundle of the input-* packages";
                      name = "inputs";
                      paths = builtins.attrValues inputs';
                    };

                    plots =
                      lib.recursiveUpdate
                      (
                        pkgs.linkFarmFromDrvs "plots" (
                          map
                          (
                            benchmarks: let
                              benchmarks' = lib.escapeShellArgs (
                                map
                                (benchmark: "${./benchmarks}/${benchmark}")
                                benchmarks
                              );
                            in
                              pkgs.runCommand
                              (
                                lib.concatMapStringsSep
                                "-"
                                (lib.removeSuffix ".json")
                                benchmarks
                              )
                              {nativeBuildInputs = [self.plot];}
                              ''
                                mkdir --parents $out
                                plot --output-directory $out -- ${benchmarks'}
                              ''
                          )
                          (
                            let
                              benchmark = builtins.elemAt benchmarks;

                              benchmarks = builtins.attrNames (
                                builtins.readDir ./benchmarks
                              );
                            in
                              [[(builtins.head benchmarks)]]
                              ++ builtins.concatMap
                              (index: [[(benchmark index) (benchmark (index + 1))]])
                              (lib.range 0 (builtins.length benchmarks - 2))
                              ++ [benchmarks]
                          )
                        )
                      )
                      {
                        meta.description = "Consecutive benchmark plots, with an overall plot combining all benchmarks";
                      };

                    workspace = pkgs.buildEnv {
                      meta.description = "Rust implementation of the performance-oriented One Billion Row Challenge (1BRC)";
                      name = "workspace";
                      paths = builtins.attrValues workspace;
                    };
                  }
                ]
            );
        }
    );
}
