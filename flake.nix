{
  description = "The Rocq Nix Toolbox";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    rec {
      lib = rec {
        forAllSystems =
          function:
          nixpkgs.lib.genAttrs [
            "x86_64-linux"
            "aarch64-linux"
            "x86_64-darwin"
            "aarch64-darwin"
          ] function;
        allPackages =
          src:
          with nixpkgs.lib;
          forAllSystems (
            system:
            let
              underlying-nix = (import ./default.nix { inherit system src; });
              instances = underlying-nix.passthru.setup.instances;
              selected-instance = underlying-nix.passthru.setup.selected-instance;
              jobsList = mapAttrsToList (
                bundleName: instance:
                let
                  listOfJobs = map (jobName: {
                    name = "${builtins.replaceStrings [ "." ] [ "-" ] bundleName}:${jobName}";
                    value = instance.pkgs.rocqPackages.${jobName} or instance.pkgs.coqPackages.${jobName};
                  }) instance.jobs;
                in
                listToAttrs listOfJobs
              ) instances;
            in
            (foldl mergeAttrs { } jobsList)
            # // {
            #   default = selected-instance.this-pkg;
            # }
          );
      };
      templates.default = {
        path = ./template;
        description = "Initialize the Rocq Nix Toolbox in a new project";
      };
      packages = lib.allPackages ./.;
    };
}
