# Writing bundles

The function `mkOverlay` takes an input an attribute set describing
the modifications that the overlay should apply. This set is what we call a **bundle**.

This page gives a description of all the different ways one can populate
the argument of `mkOverlay` in order to create an overlay that
provides their needs.


## Modifying rocqPackages

You can override the version of the rocq-core package like any other one.
This change of version will cascade to all the packages in rocqPackages.
```Nix
rocqPackages.rocq-core.override.version = "9.0";
```

You can also override the version of any package in rocqPackages.
```Nix
rocqPackages.mathcomp.override.version = "2.5.0";
```

If the overridden version is not in nixpkgs, rocqPackages will try to fetch the corresponding
github tag. You can also put commit or branch name in the `version` file which will also be
fetched from the git repository.
This will make you build not reproducible, and you have to build with flag `--impure`.
```Nix
rocqPackages.parseque.override.version = "775932fb40d7d534fb4727ea8fd0a3d20fae5fc2"; # Non-reproducible !
```

If you want to stay reproducible, you can override the source directly.
In that case, you'll need to specify a version otherwise nixpkgs might try to download its
own version of the package and fail.
```Nix
rocqPackages.rocq-elpi.overrideAttrs.src = inputs.rocq-elpi;
rocqPackages.rocq-elpi.override.version = "custom";
```


## Modifying coqPackages
The same options allows you to change `coqPackages`.
Here is a sample example implementing all the examples above.

```Nix
{
    coqPackages.coq.override.version = "9.0";
    coqPackages.math-comp.override.version = "2.5.0";
    coqPackages.parseque.override.version = "775932fb40d7d534fb4727ea8fd0a3d20fae5fc2";
    coqPackages.coq-elpi.overrideAttrs.src = inputs.rocq-elpi;      
    coqPackages.coq-elpi.override.version = "custom";
}
```
