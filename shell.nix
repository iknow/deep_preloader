with (import <nixpkgs> {});
let
  env = bundlerEnv {
    name = "bundler-env";
    gemdir  = ./nix/gem;
    ruby = ruby_3_0;
  };
in stdenv.mkDerivation {
  name = "shell";
  buildInputs = [ env ];
}
