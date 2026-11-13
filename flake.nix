{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
      lib = nixpkgs.lib;

      # Gets the transitivity closure of the second argument according to the relation in the first argument.
      # The first argument is an attribute set of list of strings describing for each string its outwards adjacency list
      # Example: transitiveClosure { a = ["b" "c"]; b = []; c = ["b" "e"]; d = ["c"]; e = []; } ["d"] is ["d" "c" "b" "e"]
      # This function encodes sets as attributes sets where all values are true
      transitiveClosure = rel: l:
        lib.attrNames <| lib.fixedPoints.converge
          (x: x // lib.mergeAttrsList (lib.map (n: lib.genAttrs rel.${n} (_: true)) (lib.attrNames x)))
          (lib.genAttrs l (_: true));

      # Generates a nixpkgs overlay from the configuration attribute set
      # The options of this attribute set are described in bundle-config.md
      mkOverlay = bundleOverrides: let
        rocqPackagesOverrides = bundleOverrides.rocqPackages or {};
        rocqPackagesOverridden = prev: lib.mapAttrs (pkg: overrides: ( # For each ${pkg} overriden with ${overrides}
          if (lib.attrsets.isDerivation overrides)
          then (overrides) # If ${overrides} is a derivation, we use it as our new package
          else ((prev.${pkg}.override (overrides.override or {})).overrideAttrs (overrides.overrideAttrs or {})) # Else, we override the package with the contents of ${overrides}.override
        )) rocqPackagesOverrides;
      in (final: prev: {
        rocqPackages = prev.rocqPackages.overrideScope (finalR: prevR: rocqPackagesOverridden prevR);
      });

      # Turns an attribute set of overlays (for example, the `overlays` output of a flake),
      # and a function taking a system name as a string and turning it into an attribute set to complete it
      exportOverlays = overlays: extraPackages:
        lib.throwIfNot (lib.isAttrs overlays) "First argument of `exportOverlays` should be an attribute set of nixpkgs overlays" <|
        lib.throwIfNot (lib.isFunction extraPackages) "Second argument of `exportOverlays` should be a function taking one string argument and returning an attribute set" <|
        lib.genAttrs lib.systems.flakeExposed (system: # For each flake exposed system
          lib.throwIfNot (lib.isAttrs (extraPackages system)) "Second argument of `exportOverlays` should be a function taking one string argument and returning an attribute set" <|
          (lib.mapAttrs ( ovName: overlay:
            import nixpkgs { inherit system; overlays = [overlay];}
          ) overlays) //
          (extraPackages system)
        )
      ;

      # First argument is either an attributeSet linking packages names to nix files paths,
      # or a function taking the "final" pkgs and return an attribute set linking packages names to packages derivations
      mkRocqRecipesOverlay = packagesInput:
        let packages =
          if (lib.isAttrs packagesInput)
          then (pkgs: lib.mapAttrs (pkgName: pkgRecipe:
              lib.throwIfNot (lib.isPath pkgRecipe) "First argument of `mkRocqRecipesOverlay`, if it is an attribute set, should only contain paths" <|
              pkgs.callPackage pkgRecipe {}
            ) packagesInput
          ) else (
              lib.throwIfNot (lib.isFunction packagesInput) "First argument of `mkRocqRecipesOverlay`, if it isn't an attribute set, should be a function taking a pkgs instance" packagesInput
          );
        in (final: prev: {rocqPackages = prev.rocqPackages.overrideScope (finalR: prevR: packages finalR);});

      # A derivation constructing a github action file for a name, an overlay and a given set of jobs
      githubAction = name: overlay: jobs: let
        inherit (import ./action.nix { inherit lib; }) mkAction;
        system = "x86_64-linux"; # actions are only built for x64-linux
        pkgs = import nixpkgs { inherit system; };
        rocqPackages = (import nixpkgs { inherit system; overlays = [ overlay ]; }).rocqPackages;
        genCI = import ./deps.nix { inherit lib rocqPackages; };
        deps = genCI.pkgsDeps;
        allDependencies = transitiveClosure deps jobs;
        allReverseDependencies = transitiveClosure genCI.pkgsRevDeps jobs;
        requiredJobs = allDependencies ++ allReverseDependencies;
        action = mkAction {
          cachix = {}; #TODO support cachix ?
          jobs = requiredJobs;
          bundles = name;
          inherit deps;
          push-branches = [ "master" ]; # We only push on the following branches
        };
        jsonAction = pkgs.writeTextFile {
          name = "github-action-${name}.json";
          text = builtins.toJSON action;
        };
      in builtins.trace (requiredJobs) <| pkgs.runCommand "github-action-${name}.yml" {} ''
        cat ${jsonAction} | ${pkgs.haskellPackages.yaml.bin}/bin/json2yaml > $out
      '';

      # A derivation constructing github action files for a given attrset of overlays and a given list of jobs
      githubActions = overlays: jobs: let
        system = "x86_64-linux"; # actions are only built for x64-linux
        pkgs = import nixpkgs { inherit system; };
      in pkgs.linkFarm "github-actions" <| lib.attrsets.mapAttrsToList (name: overlay: {
          name = "github-action-${name}.yml";
          path = githubAction name overlay jobs;
        }) overlays;

  in {
      inherit mkOverlay exportOverlays nixpkgs mkRocqRecipesOverlay githubActions;
      composeOverlays = lib.composeManyExtensions;
  };
}
