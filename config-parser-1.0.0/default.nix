# This file is a toolbox file to parse a ./nix/config.nix
# file in format 1.0.0
with builtins;
{ config, # in format 1.0.0
  nixpkgs, # source directory for nixpkgs to provide overlays
  pkgs ? import ../nixpkgs {}, # some instance of pkgs for libraries
  src ? ./., # the source directory
  overlays-dir,
  rocq-overlays-dir,
  coq-overlays-dir,
  ocaml-overlays-dir,
  override ? {},
  coq-override ? {},
  ocaml-override ? {},
  global-override ? {},
  lib,
}@initial:
with lib;
let config = import ./normalize.nix
  { inherit (initial) src lib config nixpkgs; };
in with config; let

  bundle-ppaths = bundle:
    let
      path-to-attribute = config.path-to-attribute or [ "rocqPackages" ];
    in {
      # not configurable from config.nix:
      rocq = path-to-attribute ++ [ config.attribute ];
      shell = path-to-attribute ++ [ config.shell-attribute ];
    };

  # preparing bundles
  bundles = let
      mk-main = path: j:
        setAttrByPath path
        { override.version = "${config.src}";
          job = j;
          main-job = true; };
      mk-bundles = pre: x:
        setAttrByPath pre (mapAttrs (n: v: {override.version = v;}) x);
    in mapAttrs
    (_: i:
      let ppaths = bundle-ppaths i; in
      foldl recursiveUpdate {} (
        [ (mk-main ppaths.shell config.shell-attribute)
          (mk-main ppaths.rocq config.attribute)
          i
          (mk-bundles [ "rocqPackages" ] override)
          (mk-bundles [ "ocamlPackages" ] ocaml-override)
          (mk-bundles [ ] global-override)
        ])) config.bundles;

  buildInputFrom = pkgs: str:
    pkgs.rocqPackages.${str} or pkgs.ocamlPackages.${str} or pkgs.${str};

  mk-instance = bundleName: bundle: let
    overlays = import ./overlays.nix
      { inherit lib overlays-dir rocq-overlays-dir coq-overlays-dir ocaml-overlays-dir bundle;
        inherit (config) attribute pname shell-attribute src; };

    pkgs = import config.nixpkgs { inherit overlays; };

    ci = import ./ci.nix { inherit lib this-shell-pkg pkgs bundle; };

    genCI = import ../deps.nix
      { inherit lib;
        inherit (pkgs) rocqPackages; };
    jsonPkgsDeps = toJSON genCI.pkgsDeps;
    jsonPkgsRevDeps = toJSON genCI.pkgsRevDeps;

    jobs = let
        jdeps = genAttrs ci.mains (n: genCI.pkgsRevDepsSet.${n} or {});
      in
      attrNames (removeAttrs
        (jdeps // genAttrs ci.jobs (_: true)
        // foldAttrs (_: _: true) true (attrValues jdeps))
        ci.excluded);

    inherit (import ../action.nix { inherit lib; }) mkAction;
    action = mkAction {
      inherit (config) cachix;
      inherit jobs;
      bundles = bundleName;
      deps = genCI.pkgsDeps;
    } {
      push-branches = bundle.push-branches or [ "master" ];
    };
    jsonAction = toJSON action;
    jsonActionFile = pkgs.writeTextFile {
      name = "jsonAction";
      text = jsonAction;
    };

    patchBIPkg = pkg:
      let bi = map (buildInputFrom pkgs) (config.buildInputs or []); in
      if bi == [] then pkg else
      pkg.overrideAttrs (o: { buildInputs = o.buildInputs ++ bi;});

    ppaths = bundle-ppaths bundle;
    notfound-ppath = throw "config-parser-1.0.0: not found: ${toString ppaths.rocq}";
    notfound-shell-ppath = throw "config-parser-1.0.0: not found: ${toString ppaths.shell}";
    this-pkg = patchBIPkg (attrByPath ppaths.rocq notfound-ppath pkgs);
    this-shell-pkg = patchBIPkg (attrByPath ppaths.shell (attrByPath ppaths.rocq notfound-ppath pkgs) pkgs);

    in rec {
      inherit bundle pkgs this-pkg this-shell-pkg ci;
      inherit jsonPkgsDeps jsonPkgsRevDeps;
      inherit action jsonActionFile;
      inherit jobs;
      jsonBundle = toJSON bundle;
    };
  in
{
  instances = mapAttrs mk-instance bundles;
  inherit bundles config;
}
