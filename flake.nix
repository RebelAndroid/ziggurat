{
  description = "A devShell example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system:
        let pkgs = import nixpkgs { inherit system; }; in
        with pkgs; {
          devShells.default = mkShell {
            buildInputs = [
              zig
              zls
              xorriso
              qemu_kvm
              parted
              gdb
            ];
          };
        }
    );
}
