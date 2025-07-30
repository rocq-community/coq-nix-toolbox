# IDEA: do most of the resolution on longnames
# check why we need shortnames as output?

# shortname: mathcomp-ssreflect
# longname: coq8.20-mathcomp-ssreflect-2.2.0
{ lib, coqPackages }:
with builtins; with lib;
let
  # keep all derivations inside coqPackages
  initialCoqPkgs = filterAttrs (_: isDerivation) coqPackages;
  # building a map longnames -> shortnames
  canonicalShortname =
     mapAttrs' (n: v: { name = "${v.name}"; value = n; }) initialCoqPkgs;
  # probably filtering out duplicates? (mathcomp-ssreflect = ssreflect,...)
  # keeping only packages whose shortname is the canonical one (determined just above)
  coqPkgs = filterAttrs (sn: _: elem sn (attrValues canonicalShortname)) initialCoqPkgs;
  # a map name -> list (shortname of derivations from {propagatedB,b}uildInputs)
  # keeping only derivations in coqPackages
  pkgsDeps =
    let
      # takes a derivation [x] as input and outputs a list
      # [ shortname of x ] if it exists, or []
      findInput = x: let n = if isNull x then null else
                             canonicalShortname."${x.name}" or null; in
                     if isNull n then [ ] else [ n ];
      # flattens arbitrary nested list in a list
      # whose elements are not lists anymore
      deepFlatten = l: if !isList l then l else if l == [] then []  else
        (if isList (head l) then deepFlatten (head l) else [ (head l) ])
        ++ deepFlatten (tail l);
    in
      flip mapAttrs coqPkgs (n: v: flatten
        (map findInput (deepFlatten [v.buildInputs v.propagatedBuildInputs]))
      );
  # list of all canonical shortnames, topologically sorted
  # according to dependencies (first has no dependencies)
  pkgsSorted = (toposort (x: y: elem x pkgsDeps.${y}) (attrNames coqPkgs)).result;
  # done: map canonical shortname -> its currently known reverse dependencies
  # as an attrSet shortname -> bool (where the boolean is always true)
  pkgsRevDepsSetNoAlias = foldl (done: p: foldl (done: d:
        done // { ${p} = done.${p} or {}; }
        // { ${d} = (done.${d} or {}) // { ${p} = true;} // (done.${p} or {});}
      )  done pkgsDeps.${p}
    ) {} (reverseList pkgsSorted);
  # map shortname -> set of shortnames (encoded as above)
  # for all shortnames (not just canonical ones)
  pkgsRevDepsSet = mapAttrs
     (_: p: let pname = canonicalShortname.${p.name} or p.name; in
       pkgsRevDepsSetNoAlias.${pname} or {}) initialCoqPkgs;
  # map shortname -> list of shortnames
  pkgsRevDeps = mapAttrs (n: v: attrNames v) pkgsRevDepsSet;
in
{
  inherit pkgsDeps pkgsRevDeps pkgsRevDepsSet;
}
