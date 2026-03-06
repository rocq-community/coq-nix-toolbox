{
  description = "The Coq Nix Toolbox is a set of helper scripts to ease setting up a Coq project for use with Nix, for Nix and non-Nix users alike.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
      lib = nixpkgs.lib;
      get-path = src: f: let local = src + "/.nix/${f}"; in
        if lib.pathExists local then local else ./. + "/.nix/${f}";
      listToAttrs2d = namesX: namesY: nameFormer: attrFormer: # [String] -> [String] -> (String -> String -> String) -> (String -> String -> Any) -> AttrSet
        lib.listToAttrs (lib.concatMap (x: map (y: {name = nameFormer x y; value = attrFormer x y;}) namesY) namesX)
      ;
    in {

    mkRocqProject = import ./.;

    mkRocqFlakesPackages = {
      src,
      config-file ? get-path src "config.nix",
      fallback-file ? get-path src "fallback-config.nix",
      nixpkgs-file ? get-path src "nixpkgs.nix",
      shellHook-file ? get-path src "shellHook.sh",
      overlays-dir ? get-path src "overlays",
      rocq-overlays-dir ? get-path src "rocq-overlays",
      coq-overlays-dir ? get-path src "coq-overlays",
      ocaml-overlays-dir ? get-path src "ocaml-overlays",
      config ? {},
      override ? {},
      coq-override ? {},
      ocaml-override ? {},
      global-override ? {},
    }: let
      options = {
        inherit src;
        inherit config-file fallback-file nixpkgs-file shellHook-file overlays-dir rocq-overlays-dir coq-overlays-dir ocaml-overlays-dir;

        inherit config override coq-override ocaml-override global-override;

        withEmacs = false; # TODO this should be made a custom flake output

        inNixShell = false;
        print-env = false;
        do-nothing = false;
        update-nixpkgs = false;
        ci-matrix = false;
      };
      theconfig = import config-file;
      bundles = lib.attrsets.attrNames theconfig.bundles;
      default-bundle = theconfig.default-bundle or (builtins.throw "Project did not define a default bundle");
      getJobs = pkgs: let
        bundleData = ((import ./. { inherit src; do-nothing = true; pkgs = (import nixpkgs {system = "x86_64-linux";});})).setup.instances; #TODO Remove system dependency here
        in lib.lists.unique (lib.concatLists (map (x: x.jobs) (lib.attrValues bundleData)));
      # TODO add default job and bundle
      # TODO generate flake output rocq-9-0 when finding a dot in job or bundle name (rocq-9.0 -> rocq-9-0). Keeps the other name, just in case
      mkCNTDerivation = pkgs: job: bundle: let
        out = import ./default.nix (options // { inherit pkgs job bundle; });
      in if out == [] then null else builtins.head out;

    in
      lib.attrsets.genAttrs lib.systems.flakeExposed (system: let pkgs = import nixpkgs {inherit system;}; in
        listToAttrs2d (getJobs pkgs) bundles (job: bundle: "${job}_${bundle}") (mkCNTDerivation pkgs) //
          lib.attrsets.genAttrs (getJobs pkgs) (job: mkCNTDerivation pkgs job default-bundle) # Default bundles
      );
  };
}
