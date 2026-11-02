{
  fetchFromGitHub,
  python3Packages,
  lib,
}:
python3Packages.buildPythonApplication {
  pname = "nix-auto-follow";
  version = "0-unstable-2026-10-24";
  pyproject = true;
  src = fetchFromGitHub {
    owner = "fzakaria";
    repo = "nix-auto-follow";
    rev = "862934da03ba4d2167038c374a9ad7220cde2829";
    hash = "sha256-OSCik/GdfMNIUEExmiu/+kXbC7dQNSesDJLvvvuksvk=";
  };
  build-system = with python3Packages; [
    setuptools
    setuptools-scm
  ];
  env.SETUPTOOLS_SCM_PRETEND_VERSION = "0.0.0";
  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  pythonImportsCheck = [ "nix_auto_follow.cli" ];
  meta = {
    mainProgram = "auto-follow";
    homepage = "https://github.com/fzakaria/nix-auto-follow";
    license = lib.licenses.mit;
  };
}
