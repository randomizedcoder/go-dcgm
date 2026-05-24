{
  pkgs,
  lib,
  src,
}:

let
  constants = import ../constants.nix;

  goPkg = pkgs.go_1_26 or pkgs.go;
  buildGoModule = pkgs.buildGoModule.override { go = goPkg; };

  go-dcgm = import ./library.nix {
    inherit
      lib
      src
      constants
      buildGoModule
      ;
  };
in
{
  inherit go-dcgm;
}
