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
  system
}@initial:
with lib;
let config = import ./normalize.nix
  { inherit (initial) src lib config nixpkgs system; };
in with config; let

  bundle-ppaths = bundle:
    let
      path-to-attribute = config.path-to-attribute or [ "rocqPackages" ];
      coq-path-to-attribute = config.path-to-attribute or [ "coqPackages" ];
      path-to-shell-attribute =
        if hasAttr config.shell-attribute (bundle.rocqPackages or {})
        then path-to-attribute else coq-path-to-attribute;
    in {
      # not configurable from config.nix:
      rocq = path-to-attribute ++ [ config.attribute ];
      coq = coq-path-to-attribute ++ [ config.coq-attribute ];
      shell = path-to-shell-attribute ++ [ config.shell-attribute ];
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
        optional (i ? coqPackages) (mk-main ppaths.shell config.shell-attribute)
        ++ optional ((i ? rocqPackages) && !(config.no-rocq-yet)) (mk-main ppaths.rocq config.attribute)
        ++ optional (i ? coqPackages) (mk-main ppaths.coq config.coq-attribute)
        ++ [
             i
             (mk-bundles [ "rocqPackages" ] override)
             (mk-bundles [ "coqPackages" ] coq-override)
             (mk-bundles [ "ocamlPackages" ] ocaml-override)
             (mk-bundles [ ] global-override)
        ])) config.bundles;

  buildInputFrom = pkgs: str:
    pkgs.rocqPackages.${str} or pkgs.coqPackages.${str} or pkgs.ocamlPackages.${str} or pkgs.${str};

  mk-instance = bundleName: bundle: let
    overlays = import ./overlays.nix
      { inherit lib overlays-dir rocq-overlays-dir coq-overlays-dir ocaml-overlays-dir bundle;
        inherit (config) attribute coq-attribute no-rocq-yet pname shell-attribute shell-pname src; };

    pkgs = import config.nixpkgs { inherit overlays system; };

    ci = import ./ci.nix { inherit lib this-shell-pkg pkgs bundle; };

    genCI = import ../deps.nix
      { inherit lib; coqPackages =
        if bundle ? isRocq then pkgs.rocqPackages else pkgs.coqPackages; };
    jsonPkgsDeps = toJSON genCI.pkgsDeps;
    jsonPkgsRevDeps = toJSON genCI.pkgsRevDeps;
    jsonPkgsSorted = toJSON genCI.pkgsSorted;

    jobs = let
        jdeps = genAttrs ci.mains (n: genCI.pkgsRevDepsSet.${n} or {});
      in
      attrNames (removeAttrs
        (jdeps // genAttrs ci.jobs (_: true)
        // foldAttrs (_: _: true) true (attrValues jdeps))
        ci.excluded);

    inherit (import ../action.nix { inherit lib; }) mkJobs mkAction;
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
    notfound-ppath = throw "config-parser-1.0.0: not found: ${toString ppaths.coq}";
    notfound-shell-ppath = throw "config-parser-1.0.0: not found: ${toString ppaths.shell}";
    this-pkg = patchBIPkg (attrByPath ppaths.coq notfound-ppath pkgs);
    this-shell-pkg = patchBIPkg (attrByPath ppaths.shell (attrByPath ppaths.coq notfound-ppath pkgs) pkgs);

    in rec {
      inherit bundle pkgs this-pkg this-shell-pkg ci genCI;
      inherit jsonPkgsDeps jsonPkgsSorted jsonPkgsRevDeps;
      inherit action jsonAction jsonActionFile;
      inherit jobs;
      jsonBundle = toJSON bundle;
    };
  in
{
  instances = mapAttrs mk-instance bundles;
  inherit bundles config;
}
