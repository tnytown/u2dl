{
  inputs = {
    nixpkgs.url = "nixpkgs/release-20.09";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }: utils.lib.eachDefaultSystem
    (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShell = pkgs.stdenv.mkDerivation {
          name = "csci4061";

          buildInputs = with pkgs; [
            fish curl ffmpeg
          ];
        };
      });
}
