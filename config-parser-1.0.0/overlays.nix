{ overlays-dir, lib, coq-overlays-dir, ocaml-overlays-dir, task }:
with builtins; with lib;
let
  mk-overlay = path: self: super:
    if !pathExists path then {}
    else mapAttrs (x: _v: self.callPackage (path + "/${x}") {}) (readDir path);
  do-override = pkg: cfg:
    let pkg' = if cfg?override
        then pkg.override or (x: pkg) cfg.override else pkg; in
      if cfg?overrideAttrs
      then pkg'.overrideAttrs cfg.overrideAttrs else pkg';
  nixpkgs-overrides =
    self: super: mapAttrs (n: ov: do-override super.${n} ov)
      (removeAttrs task [ "coqPackages" "ocamlPackages" ]);
  ocaml-overrides =
    self: super: mapAttrs (n: ov: do-override super.${n} ov)
      (task.ocamlPackages or {});
  coq-overrides =
    self: super: mapAttrs
      (n: ov: do-override (super.${n} or
        (makeOverridable self.mkCoqDerivation {
          pname = "${n}"; version = "${src}";
        })) ov)
      (task.coqPackages or {});
  fold-override = foldl (fpkg: override: fpkg.overrideScope' override);
  in
[
  (mk-overlay overlays-dir)
  nixpkgs-overrides
  (self: super: { coqPackages = fold-override super.coqPackages ([
    (mk-overlay coq-overlays-dir)
    coq-overrides
    (self: super: { coq = super.coq.override {
      customOCamlPackages = fold-override super.coq.ocamlPackages [
        (mk-overlay ocaml-overlays-dir)
        ocaml-overrides
      ];};})
  ]);})
  (self: super: { coqPackages =
    super.coqPackages.filterPackages
      (! (super.coqPackages.coq.dontFilter or false)); })
]