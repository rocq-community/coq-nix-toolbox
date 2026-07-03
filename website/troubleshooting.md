# Troubleshooting

This page aims at providing hints and solutions to the most common issues while facing the nix toolbox.


## Common Issues

### in pure evaluation mode, 'fetchTarball' requires a 'sha256' argument
This issues often means that nixpkgs tried to download its own version of the source of a package.
This can happen when you have overriden a `version` argument to a version that is not registered in nixpkgs.

The simplest solution is to pass the flag `--impure` to the nix builder, which will make your build non-reproducible.
This can be useful for test purposes.

If you want to keep reproducibility, you have to override the source of the final derivation, so that nixpkgs
will not even try do download it. The following code snippet can do it.
For you to guess the hash, you can keep it blank, then launch you build. Nix will produce an error telling you
the expected hash, and from this you can input in your file the hash that Nix has given you.
```Nix
rocqPackages.myPackage.overrideAttrs.src = lib.fetchFromGithub {
    owner = "repo-owner";
    repo = "repo-name";
    rev = "commit number or release tag";
    hash = "";
};
```
