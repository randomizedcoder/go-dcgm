{
  lib,
  src,
  constants,
  buildGoModule,
}:

buildGoModule {
  pname = "go-dcgm";
  version = constants.goDcgm.version;
  inherit src;

  vendorHash = "sha256-pZmhmCU9YjAKc/DuKFe7yRYL9hf8eGN9O1w492Qk0Ms=";

  env.CGO_ENABLED = "1";

  ldflags = constants.goDcgm.ldflags;

  doCheck = false;

  meta = with lib; {
    description = "Go bindings for NVIDIA Data Center GPU Manager (DCGM)";
    homepage = "https://github.com/NVIDIA/go-dcgm";
    license = licenses.asl20;
  };
}
