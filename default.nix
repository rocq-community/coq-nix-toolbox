# This file is a toolbox file to parse a .nix directory and make
# 1. a nix overlay
# 2. a shell and a build derivation
with builtins;
let
  get-path = src: f: let local = src + "/.nix/${f}"; in
    if pathExists local then local else ./. + "/.nix/${f}";
in
{
  src ? ./., # provide the current directory
  config-file ? get-path src "config.nix",
  fallback-file ? get-path src "fallback-config.nix",
  nixpkgs-file ? get-path src "nixpkgs.nix",
  shellHook-file ? get-path src "shellHook.sh",
  overlays-dir ? get-path src "overlays",
  rocq-overlays-dir ? get-path src "rocq-overlays",
  coq-overlays-dir ? get-path src "coq-overlays",
  ocaml-overlays-dir ? get-path src "ocaml-overlays",
  ci-matrix ? false,
  config ? {},
  override ? {},
  coq-override ? {},
  ocaml-override ? {},
  global-override ? {},
  pkgs ? null,
  withEmacs ? false,
  print-env ? false,
  do-nothing ? false,
  update-nixpkgs ? false,
  job ? null,
  bundle ? null,
  inNixShell ? null
}@args:
let
  optionalImport = f: d:
    if (isPath f || isString f) && pathExists f then import f else d;
  do-nothing = (args.do-nothing or false) || update-nixpkgs || ci-matrix;
  initial = {
    config = (optionalImport config-file (optionalImport fallback-file {}))
              // config;
    nixpkgs = optionalImport nixpkgs-file (throw "cannot find nixpkgs");
    pkgs = if (args.pkgs or null) == null then (import initial.nixpkgs {}) else args.pkgs;
    #pkgs = args.pkgs or import initial.nixpkgs {};
    src = src;
    lib = initial.pkgs.coqPackages.lib;
    inherit overlays-dir rocq-overlays-dir coq-overlays-dir ocaml-overlays-dir;
    inherit global-override override coq-override ocaml-override;
  };
  my-throw = x: throw "Coq nix toolbox error: ${x}";
in
with initial.lib; let
  inNixShell = args.inNixShell or trivial.inNixShell;
  setup = switch initial.config.format [
    { case = "1.0.0";        out = import ./config-parser-1.0.0 initial; }
    { case = x: !isString x; out = my-throw "config.format must be a string."; }
  ] (my-throw "config.format ${initial.config.format} not supported");
  instances = setup.instances;
  selectedBundle = let dflt = setup.config.default-bundle; in
    if isNull bundle || bundle == "_all" then dflt else bundle;
  allBundles = bundle == "_all";
  selected-instance = instances."${selectedBundle}";
  shellHook = readFile shellHook-file
      + optionalString print-env "\nprintNixEnv; exit"
      + optionalString update-nixpkgs "\nupdateNixpkgsUnstable; exit"
      + optionalString ci-matrix "\nnixBundles; exit";
  jsonBundles = toJSON (attrNames setup.bundles);
  jsonBundleSet = toJSON setup.bundles;
  jsonBundle = toJSON selected-instance.bundle;
  coq-lsp = if selected-instance.pkgs.coqPackages?coq-lsp then
     [ selected-instance.pkgs.coqPackages.coq-lsp ] else [];
  vscoq = if selected-instance.pkgs.coqPackages?vscoq-language-server then
     [ selected-instance.pkgs.coqPackages.vscoq-language-server ] else [];
  emacs = selected-instance.pkgs.emacs.pkgs.withPackages
    (epkgs: with epkgs.melpaPackages; [ proof-general ]);
  emacsInit = ./emacs-init.el;

  jsonSetupConfig = toJSON setup.config;

  ciByBundle = flip mapAttrs setup.instances (_: v:
    mapAttrs (_: x: map (x: x.name) x) v.ci.set);
  jsonCIbyBundle = toJSON ciByBundle;

  ciByJob =
    let
      jobs-list = attrValues (flip mapAttrs ciByBundle (tn: tv:
        flip mapAttrs tv (jn: jv: {${tn} = jv;})));
      push-list = foldAttrs (n: a: [n] ++ a) [];
    in
      flip mapAttrs (push-list jobs-list)
        (jn: jv: mapAttrs (_: flatten) (push-list jv));
  jsonCIbyJob = toJSON ciByJob;

  mkDeriv = shell:
  if !inNixShell then shell
  else with selected-instance; shell.overrideAttrs (old: {
    inherit (setup.config) nixpkgs coqproject;
    inherit jsonBundle jsonBundles jsonSetupConfig jsonCIbyBundle jsonBundleSet
            jsonCIbyJob shellHook selectedBundle
            jsonPkgsDeps jsonPkgsRevDeps jsonActionFile;

    bundles = attrNames setup.bundles;

    passthru = (old.passthru or {}) // {inherit action; inherit (selected-instance) pkgs;};

    COQBIN = optionalString (!do-nothing) "";

    coq_version = optionalString (!do-nothing)
       selected-instance.pkgs.coqPackages.coq.coq-version;

    nativeBuildInputs = optionals (!do-nothing)
      ((old.nativeBuildInputs or []) ++ coq-lsp ++ vscoq) ++ [ selected-instance.pkgs.remarshal ];

    propagatedNativeBuildInputs = optionals (!do-nothing)
      (old.propagatedNativeBuildInputs or []);

    buildInputs = optionals (!do-nothing) (old.buildInputs or []);

    propagatedBuildInputs = optionals (!do-nothing)
      (old.propagatedBuildInputs or []);
  }
  // optionalAttrs withEmacs {
      inherit emacsInit;
      emacsBin = "${emacs}" + "/bin/emacs";
  });

  nix-ci = job: map mkDeriv (if allBundles
    then flatten (mapAttrsToList (_: i: i.ci.subpkgs job) instances)
    else instances.${selectedBundle}.ci.subpkgs job);
  nix-default = if allBundles
    then mapAttrsToList (_: i: mkDeriv i.this-shell-pkg) instances
    else mkDeriv selected-instance.this-shell-pkg;
  nix-auto = if isNull job then nix-default else nix-ci job;
  in
if !isDerivation nix-auto then nix-auto
else nix-auto.overrideAttrs (o: {
  passthru = (o.passthru or {})
             // { inherit initial setup shellHook;
                  inherit nix-default nix-ci nix-auto; };
})
