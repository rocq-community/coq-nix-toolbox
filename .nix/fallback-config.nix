with (import (import ./nixpkgs.nix) {}).lib;
{
  ## DO NOT CHANGE THIS
  format = "1.0.0";
  ## unless you made an automated or manual update
  ## to another supported format.

  ## The attribute to build, either from nixpkgs
  ## of from the overlays located in `.nix/rocq-overlays` or `.nix/coq-overlays`
  attribute = "rocq-core";
  coq-attribute = "coq";
  shell-attribute = "coq-shell";
  src = ../coq-shell;

  ## select an entry to build in the following `bundles` set
  ## defaults to "default"
  default-bundle = "8.18";

  ## write one `bundles.name` attribute set per
  ## alternative configuration, the can be used to
  ## compute several ci jobs as well
  bundles = (genAttrs [ "8.18" "8.19" "8.20" "9.0" "9.1" ]
    (v: {
      rocqPackages.rocq-core.override.version = v;
      rocqPackages.rocq-core.job = false;
      coqPackages.coq.override.version = v;
      coqPackages.bignums.job = true;
      coqPackages.coq-elpi.job = true;
      coqPackages.hierarchy-builder.job = true;
      coqPackages.stdlib.job = true;
    })) // {
    master = {
      rocqPackages.rocq-core.override.version = "master";
      rocqPackages.rocq-core.job = false;
      coqPackages.coq.override.version = "master";
      coqPackages.heq.job = false;
      coqPackages.stdlib.job = false;
    };
    "rocq-9.0" = {
      rocqPackages.rocq-core.override.version = "9.0";
    };
    "rocq-9.1" = {
      rocqPackages.rocq-core.override.version = "9.1";
    };
    "rocq-master" = {
      rocqPackages.rocq-core.override.version = "master";
      rocqPackages.stdlib.override.version = "master";
    };
  };

  cachix.coq = {};
  cachix.math-comp = {};
  cachix.coq-community.authToken = "CACHIX_AUTH_TOKEN";
}
