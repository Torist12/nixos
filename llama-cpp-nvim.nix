# llama-cpp-nvim.nix
#
# Modulo home-manager: IA local no nvim (llama.cpp via nixpkgs + llama.vim).
# - Instala pkgs.llama-cpp (build CPU, resolve libs no NixOS).
# - Cria o wrapper ~/.local/share/llama-cpp/bin/llama-server (mesmo caminho
#   do script shell original -> o init.lua continua identico, F4/F8 iguais).
# - Copia o plugin llama.vim para ~/.local/share/nvim/site/pack/ia/opt/llama.vim.
# - Baixa os modelos GGUF do HF na 1a ativacao, de forma idempotente.
#
# Importe no seu home.nix:
#   imports = [ ./llama-cpp-nvim.nix ];
#   programs.llama-cpp-nvim.enable = true;
#
# Se voce usa flakes em modo pure, adicione --impure ao `home-manager switch`
# por causa do builtins.fetchTarball do plugin. Alternativa 100% pura:
# use pkgs.fetchFromGitHub com rev + sha256 fixos (ver comentario abaixo).

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.llama-cpp-nvim;

  # Wrapper: o init.lua chama $HOME/.local/share/llama-cpp/bin/llama-server,
  # mas o binario real vem do nixpkgs (que resolve libs/deps no NixOS).
  llamaServerWrapper = pkgs.writeShellScript "llama-server-wrapper" ''
    exec ${pkgs.llama-cpp}/bin/llama-server "$@"
  '';

  # Plugin llama.vim.
  # builtins.fetchTarball evita precisar preencher hash; funciona no
  # `home-manager switch` normal. Em flakes pure, use --impure OU
  # troque pelo bloco pinado abaixo.
  #
  # --- alternativa pinada (recomendada em flakes pure) -------------------
  # plugin = pkgs.fetchFromGitHub {
  #   owner  = "ggml-org";
  #   repo   = "llama.vim";
  #   rev    = "COLOQUE_O_COMMIT";   # ex.: "abc1234..."
  #   sha256 = "COLOQUE_O_HASH";     # obtenha com `nix-prefetch-github ggml-org llama.vim --rev <rev>`
  # };
  # ----------------------------------------------------------------------
  pluginTarball = builtins.fetchTarball {
    url = "https://github.com/ggml-org/llama.vim/archive/refs/heads/master.tar.gz";
  };
   plugin = pkgs.fetchFromGitHub {
    owner  = "ggml-org";
    repo   = "llama.vim";
    rev    = "e1ca1cc6af9da73f4ae21f810f33909d515592e6";
    sha256 = "sha256-ZMPFenkp3S+H54ocr8AgQtIoOjOd8QUfBt0Soj+DQ1k=";
  };

  # Modelos: mesmos arquivos/URLs do script shell original, mesma logica
  # (baixa so o que falta, com .parcial e retomada).
  downloadModels = pkgs.writeShellApplication {
    name = "download-llama-models";
    runtimeInputs = [ pkgs.curl pkgs.coreutils ];
    text = ''
      set -eu
      base="$HOME/.local/share/llama-cpp/models"
      mkdir -p "$base" "$base/chat"

      download() {
        name="$1"; url="$2"; dir="$3"
        dest="$dir/$name"
        if [ -s "$dest" ] && [ ! -f "$dest.parcial" ]; then
          echo "ok (ja existe): $name"
          return 0
        fi
        echo "baixando: $name"
        touch "$dest.parcial"
        curl -fL --retry 3 -C - -o "$dest" "$url"
        rm -f "$dest.parcial"
      }

      download "qwen2.5-coder-1.5b-q8_0.gguf" \
        "https://huggingface.co/ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF/resolve/main/qwen2.5-coder-1.5b-q8_0.gguf" \
        "$base"

      download "Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
        "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
        "$base/chat"
    '';
  };
in
{
  options.programs.llama-cpp-nvim = {
    enable = lib.mkEnableOption "IA local para nvim (llama.cpp + llama.vim, F4/F8)";

    autoDownloadModels = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Baixar os modelos GGUF do Hugging Face automaticamente no
        `home-manager switch`, se ainda nao estiverem em
        ~/.local/share/llama-cpp/models. Precisa de internet na 1a vez
        (~4 GB); depois tudo offline.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.llama-cpp pkgs.curl ];

    # Wrapper: mantem o caminho que o init.lua espera.
    home.file.".local/share/llama-cpp/bin/llama-server" = {
      source = llamaServerWrapper;
      executable = true;
    };

    # Plugin no lugar onde o init.lua procura (pack/ia/opt/llama.vim).
    home.file.".local/share/nvim/site/pack/ia/opt/llama.vim".source = plugin;

    # Baixa modelos na ativacao (idempotente; falha de rede so avisa).
    home.activation.downloadLlamaModels = lib.mkIf cfg.autoDownloadModels (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${downloadModels}/bin/download-llama-models || \
          echo "AVISO: falha ao baixar modelos (sem internet?). Rode depois: download-llama-models"
      ''
    );
  };
}