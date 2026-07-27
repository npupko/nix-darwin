# terminal-notifier built FROM SOURCE (native arm64) via xcbuild.
#
# Why this exists: nixpkgs' 26.05 `terminal-notifier` (pkgs/by-name/te/…) was
# changed to unpack the upstream prebuilt release .zip (`dontBuild = true`),
# and that prebuilt is x86_64-only. On aarch64-darwin it runs under Rosetta,
# and macOS raises a "Support Ending for Intel-based Apps" deprecation warning.
# terminal-notifier is abandoned upstream (last release 2017) with no native
# arm64/universal build published, so the only way to get a native binary is
# to compile the Xcode project ourselves.
#
# This is a near-verbatim copy of the xcbuild-based derivation nixpkgs itself
# shipped until recently (as of nixpkgs commit ca912fd) — it produces a native
# aarch64 binary. It's a tiny Objective-C app, so the source build is seconds,
# not minutes. Referenced from overlays.nix via callPackage.
#
# Removal: drop this file + its overlay once nixpkgs ships a native aarch64
# terminal-notifier from cache again (or you switch notifiers).
{
  apple-sdk,
  fetchFromGitHub,
  ibtool,
  lib,
  llvmPackages,
  makeBinaryWrapper,
  stdenv,
  xcbuildHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "terminal-notifier";
  version = "2.0.0";

  src = fetchFromGitHub {
    owner = "julienXX";
    repo = "terminal-notifier";
    tag = finalAttrs.version;
    hash = "sha256-Hd9cI3R2nQK2deBb5CBYz4DTHAEcO4vzqtA5qZwa1Ao=";
  };

  nativeBuildInputs = [
    ibtool
    makeBinaryWrapper
    xcbuildHook
    llvmPackages.lld
  ];

  buildInputs = [
    apple-sdk
  ];

  xcbuildFlags = [
    "-target"
    "terminal-notifier"
    "-configuration"
    "Release"
  ];

  env.NIX_CFLAGS_LINK = "-fuse-ld=lld";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{Applications,bin}
    cp -r Products/Release/terminal-notifier.app $out/Applications/
    makeWrapper \
      $out/Applications/terminal-notifier.app/Contents/MacOS/terminal-notifier \
      $out/bin/terminal-notifier \
      --chdir $out/Applications/terminal-notifier.app

    runHook postInstall
  '';

  meta = {
    description = "Send macOS User Notifications from the command-line (native aarch64 source build)";
    homepage = "https://github.com/julienXX/terminal-notifier";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "terminal-notifier";
  };
})
