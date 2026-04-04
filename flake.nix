{
  description = "The Coq Nix Toolbox is a set of helper scripts to ease setting up a Coq project for use with Nix, for Nix and non-Nix users alike.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;
      get-path =
        src: f:
        let
          local = src + "/.nix/${f}";
        in
        if lib.pathExists local then local else ./. + "/.nix/${f}";
      listToAttrs2d =
        namesX: namesY: nameFormer: attrFormer: # [String] -> [String] -> (String -> String -> String) -> (String -> String -> Any) -> AttrSet
        lib.listToAttrs (
          lib.concatMap (
            x:
            map (y: {
              name = nameFormer x y;
              value = attrFormer x y;
            }) namesY
          ) namesX
        );
      flakeOutputRenamer = lib.replaceString "." "-";
      # Renames all entries of base attrset with renamer. Keeps the old entries.
      buildAttrsRename =
        renamer: base:
        base
        // (lib.genAttrs' (lib.attrNames base) (name: {
          name = renamer name;
          value = base.${name};
        }));
      forEachSystem = f: lib.genAttrs lib.systems.flakeExposed f;
    in
    {

      mkRocqProject = import ./.;

      mkRocqFlakesPackages =
        {
          src,
          config-file ? get-path src "config.nix",
          fallback-file ? get-path src "fallback-config.nix",
          nixpkgs-file ? get-path src "nixpkgs.nix",
          shellHook-file ? get-path src "shellHook.sh",
          overlays-dir ? get-path src "overlays",
          rocq-overlays-dir ? get-path src "rocq-overlays",
          coq-overlays-dir ? get-path src "coq-overlays",
          ocaml-overlays-dir ? get-path src "ocaml-overlays",
          config ? { },
          override ? { },
          coq-override ? { },
          ocaml-override ? { },
          global-override ? { },
        }:
        let
          options = {
            inherit src;
            inherit
              config-file
              fallback-file
              nixpkgs-file
              shellHook-file
              overlays-dir
              rocq-overlays-dir
              coq-overlays-dir
              ocaml-overlays-dir
              ;

            inherit
              config
              override
              coq-override
              ocaml-override
              global-override
              ;

            inNixShell = false;
            print-env = false;
            do-nothing = false;
            update-nixpkgs = false;
            ci-matrix = false;
          };
          theconfig = import config-file;
          bundles = lib.attrsets.attrNames theconfig.bundles;
          default-bundle =
            theconfig.default-bundle or (builtins.throw "Project did not define a default bundle");
          getJobs =
            pkgs:
            let
              bundleData =
                (
                  (import ./. {
                    inherit src pkgs;
                    do-nothing = true;
                  })
                ).setup.instances;
            in
            lib.lists.unique (lib.concatLists (map (x: x.jobs) (lib.attrValues bundleData)));
          mkCNTDerivation =
            pkgs: withEmacs: job: bundle:
            let
              out = import ./default.nix (
                options
                // {
                  inherit
                    pkgs
                    job
                    bundle
                    withEmacs
                    ;
                }
              );
            in
            if out == [ ] then null else builtins.head out;

        in
        lib.attrsets.genAttrs lib.systems.flakeExposed (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
          in
          buildAttrsRename flakeOutputRenamer (
            listToAttrs2d (getJobs pkgs) bundles (job: bundle: "${job}_${bundle}") (mkCNTDerivation pkgs false)
            // listToAttrs2d (getJobs pkgs) bundles (job: bundle: "${job}_${bundle}_emacs") (
              mkCNTDerivation pkgs true
            )
            // lib.attrsets.genAttrs (getJobs pkgs) (job: mkCNTDerivation pkgs job default-bundle) # Default bundles
          )
        );
      formatter = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          treefmtConfig = {
            programs = {
              mdformat = {
                enable = true;
                settings = {
                  wrap = 80;
                  number = true;
                };
              };
              nixfmt.enable = true;
            };
          };
          treefmtEval = treefmt-nix.lib.evalModule pkgs treefmtConfig;
        in
        treefmtEval.config.build.wrapper
      );
    };
}
