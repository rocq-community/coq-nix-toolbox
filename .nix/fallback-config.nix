with (import (import ./nixpkgs.nix) {}).lib;
{
  ## DO NOT CHANGE THIS
  format = "1.0.0";
  ## unless you made an automated or manual update
  ## to another supported format.

  ## The attribute to build, either from nixpkgs
  ## of from the overlays located in `.nix/rocq-overlays` or `.nix/coq-overlays`
  attribute = "rocq-core";
  shell-attribute = "coq-shell";
  src = ../coq-shell;

  ## select an entry to build in the following `bundles` set
  ## defaults to "default"
  default-bundle = "9.0";

  ## write one `bundles.name` attribute set per
  ## alternative configuration, the can be used to
  ## compute several ci jobs as well
  bundles = genAttrs [ "8.20" ]
    (v: {
      coqPackages.coq.override.version = v;
    }) // genAttrs [ "9.0" "9.1" "9.2" "9.3" "master" ]
    (v: {
      rocqPackages.rocq-core.override.version = v;
      rocqPackages.coq.override.version = v;
      coqPackages.heq.job = false;
    });

  cachix.coq = {};
  cachix.math-comp = {};
  cachix.coq-community.authToken = "CACHIX_AUTH_TOKEN";
}
