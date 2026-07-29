# This file is a toolbox file to parse a ./nix/config.nix
# file in format 1.0.0
{
  lib,
  config,
  nixpkgs,
  src,
}@initial:
with builtins;
with lib;
let
  normalize-coqpkg =
    name: pkg:
    let
      j = pkg.job or name;
    in
    pkg
    // {
      job =
        let
          case = case: out: { inherit case out; };
        in
        switch j
          [
            (case true name)
            (case false "_excluded")
            (case isString j)
          ]
          (throw ''
            config-parser-1.0.0 normalize: job must be either:
            - true        (the name of the job is the one of the attribute,
                           this is the default behaviour)
            - false       (the package is excluded from CI, always)
            - "_excluded" (the package is excluded from CI, always)
            - "_deps"     (the package is considered by the CI as a dependency)
            - "_allJobs"  (the job is triggered only when testing all existing jobs)
            - "_all"      (the job is triggered only when testing all rocqPackages)
            - a string which corresponds both to the job name
              and an attribute in rocqPackages.
          '');
    };
  normalize-bundle =
    _name: b:
    let
      rocqPkgs = (b.coqPackages or {}) // (b.rocqPackages or {});
      normalize-pkg =
        name: pkg:
        if name != "rocqPackages" && name != "coqPackages" then pkg else mapAttrs normalize-coqpkg rocqPkgs;
      bundle = { rocqPackages = { }; } // b;
    in
      mapAttrs normalize-pkg bundle;
in
rec {
  format = "1.0.0";
  attribute = config.attribute or "template";
  shell-attribute =
    (
      if config ? shell-pname then
        warn "shell-pname is not used anymore, use shell-attribute instead"
      else
        x: x
    )
    (config.shell-attribute or attribute);
  nixpkgs = config.nixpkgs or initial.nixpkgs;
  pname = config.pname or attribute;
  coqproject = config.coqproject or "_CoqProject";
  default-bundle = config.default-bundle or "default";
  cachix = config.cachix or { coq = { }; };
  bundles = mapAttrs normalize-bundle (config.bundles or { default = { }; });
  buildInputs = config.buildInputs or [ ];
  src =
    config.src or (
      if pathExists (/. + initial.src) -> pathExists (/. + initial.src + "/.git") then
        fetchGit (
          if
            false
          # replace by a version check when supported
          # cf https://github.com/NixOS/nix/issues/1837
          then
            {
              url = initial.src;
              shallow = true;
            }
          else
            initial.src
        )
      else
        /. + initial.src
    );
}
