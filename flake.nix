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

    # Those nix-toolbox options are translated to different flake outputs
    # job
    # bundle
    # withEmacs


    # Options i think should be dropped
    #print-env ? false #-> Prints nixEnv inside nix-shell
    #ci-matrix ? false #-> Prints a list of bundles as Json
    #update-nixpkgs ? false,#-> Updates nixpkgs ... but i don't know where it does come from
    #do-nothing ? false,#-> should be useless now ?


    # Mouais
    #inNixShell ? null

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
      theconfig = import config-file;
      bundleData = ((import ./. { inherit src; do-nothing = true;})).setup.instances;
      bundles = lib.attrsets.attrNames theconfig.bundles;
      default-bundle = theconfig.default-bundle or (builtins.throw "Project did not define a default bundle");
      jobs = lib.lists.unique (lib.concatLists (map (x: x.jobs) (lib.attrValues bundleData)));
      # TODO add default job and bundle
      # TODO generate flake output rocq-9-0 when finding a dot in job or bundle name (rocq-9.0 -> rocq-9-0). Keeps the other name, just in case
      mkCNTDerivation = job: bundle: builtins.head (import ./default.nix {
        inherit src;
        inherit config-file fallback-file nixpkgs-file shellHook-file overlays-dir rocq-overlays-dir coq-overlays-dir ocaml-overlays-dir;

        inherit config override coq-override ocaml-override global-override;

        inherit job bundle;
        withEmacs = false; # TODO this should be made a custom flake output

        inNixShell = false;
        print-env = false;
        do-nothing = false;
        update-nixpkgs = false;
        ci-matrix = false;
      });
    in
      lib.attrsets.genAttrs lib.systems.flakeExposed (system:
       listToAttrs2d jobs bundles (job: bundle: "${job}_${bundle}") mkCNTDerivation //
          lib.attrsets.genAttrs jobs (job: mkCNTDerivation job default-bundle) # Default bundles
      );
  };
}
