{
  description = "A Nix flake for my Rocq project using the Rocq Nix Toolbox";
  inputs = {
    rocq-nix-toolbox.url = "github:rocq-community/coq-nix-toolbox";
  };
  outputs =
    { rocq-nix-toolbox, ... }:
    {
      packages = rocq-nix-toolbox.lib.allPackages ./.;
    };
}
