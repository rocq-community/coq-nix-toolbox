{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=master";
  };

  outputs = { self, nixpkgs }: let
      lib = nixpkgs.lib;

      # Generates a nixpkgs overlay from the configuration attribute set
      # The options of this attribute set are described in bundle-config.md
      mkOverlay = bundleOverrides: let
        rocqPackagesOverrides = bundleOverrides.rocqPackages or {};
        rocqPackagesOverridden = prev: lib.mapAttrs (pkg: overrides: ( # For each ${pkg} overriden with ${overrides}
          if (lib.attrsets.isDerivation overrides)
          then (overrides) # If ${overrides} is a derivation, we use it as our new package
          else ((prev.${pkg}.override (overrides.override or {})).overrideAttrs (overrides.overrideAttrs or {})) # Else, we override the package with the contents of ${overrides}.override
        )) rocqPackagesOverrides;
        coqPackagesOverrides = bundleOverrides.coqPackages or {};
        coqPackagesOverridden = prev: lib.mapAttrs (pkg: overrides: ( # For each ${pkg} overriden with ${overrides}
          if (lib.attrsets.isDerivation overrides)
          then (overrides) # If ${overrides} is a derivation, we use it as our new package
          else ((prev.${pkg}.override (overrides.override or {})).overrideAttrs (overrides.overrideAttrs or {})) # Else, we override the package with the contents of ${overrides}.override
        )) coqPackagesOverrides;
      in (final: prev: {
        rocqPackages = prev.rocqPackages.overrideScope (finalR: prevR: rocqPackagesOverridden prevR);
        coqPackages = prev.coqPackages.overrideScope (finalR: prevR: coqPackagesOverridden prevR);
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

      # First argument is either an attributeSet linking packages names to nix files paths,
      # or a function taking the "final" pkgs and return an attribute set linking packages names to packages derivations
      mkCoqRecipesOverlay = packagesInput:
        let packages =
          if (lib.isAttrs packagesInput)
          then (pkgs: lib.mapAttrs (pkgName: pkgRecipe:
              lib.throwIfNot (lib.isPath pkgRecipe) "First argument of `mkCoqRecipesOverlay`, if it is an attribute set, should only contain paths" <|
              pkgs.callPackage pkgRecipe {}
            ) packagesInput
          ) else (
              lib.throwIfNot (lib.isFunction packagesInput) "First argument of `mkCoqRecipesOverlay`, if it isn't an attribute set, should be a function taking a pkgs instance" packagesInput
          );
        in (final: prev: {coqPackages = prev.coqPackages.overrideScope (finalR: prevR: packages finalR);});

  in {
      inherit mkOverlay exportOverlays nixpkgs mkRocqRecipesOverlay mkCoqRecipesOverlay;
      composeOverlays = lib.composeManyExtensions;
  };
}
