# llama-cpp-nvim.nix
#
# Modulo Home Manager para IA local no Micro e no Neovim.
# - Instala llama.cpp e cria um wrapper para o llama-server.
# - Configura um servico local e um plugin Lua para o Micro (F4/F8).
# - Instala llama.vim no Neovim e baixa o modelo FIM GGUF na 1a ativacao.
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

  # Wrapper que usa o binario do nixpkgs com as dependencias corretas no NixOS.
  llamaServerWrapper = pkgs.writeShellScript "llama-server-wrapper" ''
    exec ${pkgs.llama-cpp}/bin/llama-server "$@"
  '';

  modelPath = "${config.home.homeDirectory}/.local/share/llama-cpp/models/qwen2.5-coder-1.5b-q8_0.gguf";

  microLlamaRequest = pkgs.writeShellApplication {
    name = "micro-llama-request";
    runtimeInputs = [ pkgs.curl pkgs.jq ];
    text = ''
      operation="$1"
      payload="$2"
      case "$operation" in
        completion)
          curl --fail --silent --show-error --max-time 120 \
            -H 'Content-Type: application/json' \
            --data-binary "$payload" \
            http://127.0.0.1:9931/completion \
            | jq -er '.content'
          ;;
        chat)
          curl --fail --silent --show-error --max-time 120 \
            -H 'Content-Type: application/json' \
            --data-binary "$payload" \
            http://127.0.0.1:9931/v1/chat/completions \
            | jq -er '.choices[0].message.content'
          ;;
        *)
          echo "operacao desconhecida: $operation" >&2
          exit 2
          ;;
      esac
    '';
  };

  nixai = pkgs.writeShellApplication {
    name = "nixai";
    runtimeInputs = [ pkgs.coreutils pkgs.jq microLlamaRequest ];
    text = ''
      history='[{"role":"system","content":"Você é um assistente útil. Responda diretamente em português do Brasil. Não repita a pergunta do usuário; responda ao que foi perguntado. Se faltar contexto, peça esclarecimentos."}]'
      tmpdir="$(mktemp -d)"
      spinner_pid=""

      cleanup() {
        if [[ -n "$spinner_pid" ]]; then
          kill "$spinner_pid" 2>/dev/null || true
          wait "$spinner_pid" 2>/dev/null || true
        fi
        rm -rf "$tmpdir"
      }
      trap cleanup EXIT
      trap 'exit 130' INT TERM

      show_spinner() {
        local frames='|/-'
        local index=0
        while true; do
          printf '\rIA está pensando %s' "''${frames:index++ % ''${#frames}:1}"
          sleep 0.15
        done
      }

      send_message() {
        local prompt="$1"
        local payload
        local answer

        payload="$(jq -cn \
          --argjson history "$history" \
          --arg prompt "$prompt" \
          '{model:"micro-local",messages:($history + [{role:"user",content:$prompt}]),max_tokens:512,temperature:0.3,stream:false}')"

        micro-llama-request chat "$payload" >"$tmpdir/answer" 2>"$tmpdir/error" &
        spinner_pid=$!
        show_spinner &
        local animation_pid=$!

        local request_exit=0
        wait "$spinner_pid" || request_exit=$?
        spinner_pid=""
        kill "$animation_pid" 2>/dev/null || true
        wait "$animation_pid" 2>/dev/null || true
        printf '\r\033[K'

        if (( request_exit != 0 )); then
          printf 'Erro ao consultar a IA local. Verifique se o servidor está ativo.\n' >&2
          cat "$tmpdir/error" >&2
          return 1
        fi

        answer="$(<"$tmpdir/answer")"
        printf 'IA: %s\n\n' "$answer"
        history="$(jq -cn \
          --argjson history "$history" \
          --arg prompt "$prompt" \
          --arg answer "$answer" \
          '$history + [{role:"user",content:$prompt},{role:"assistant",content:$answer}]')"
      }

      printf 'NixAI local. Digite /sair para encerrar.\n\n'
      while true; do
        if [[ $# -gt 0 ]]; then
          prompt="$*"
          set --
        else
          if ! IFS= read -r -p 'Você: ' prompt; then
            printf '\n'
            break
          fi
        fi

        case "$prompt" in
          /sair|/exit|/quit)
            break
            ;;
          "")
            continue
            ;;
        esac

        send_message "$prompt" || true
      done
    '';
  };

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

  # Baixa o modelo FIM somente quando ainda nao existe, com retomada.
  downloadModels = pkgs.writeShellApplication {
    name = "download-llama-models";
    runtimeInputs = [ pkgs.curl pkgs.coreutils ];
    text = ''
      set -eu
      base="$HOME/.local/share/llama-cpp/models"
      mkdir -p "$base"

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
    '';
  };
in
{
  options.programs.llama-cpp-nvim = {
    enable = lib.mkEnableOption "IA local no Micro e Neovim (llama.cpp)";

    autoDownloadModels = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Baixar o modelo GGUF do Hugging Face automaticamente no
        `home-manager switch`, se ainda nao estiverem em
        ~/.local/share/llama-cpp/models. Precisa de internet na 1a vez
        (~1,6 GB); depois o modelo fica offline.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.llama-cpp pkgs.curl microLlamaRequest nixai ];

    # Wrapper em caminho estavel para uso pelo Neovim e por outros scripts.
    home.file.".local/share/llama-cpp/bin/llama-server" = {
      source = llamaServerWrapper;
      executable = true;
    };

    # Plugin opcional do Neovim.
    home.file.".local/share/nvim/site/pack/ia/opt/llama.vim".source = plugin;

    home.file.".config/micro/plug/llama_ai/llama_ai.lua".source = ./micro-llama.lua;
    home.file.".config/micro/plug/llama_ai/repo.json".source = ./micro-llama-repo.json;

    systemd.user.services.llama-micro-server = {
      Unit = {
        Description = "llama.cpp local inference server for Micro";
        After = [ "default.target" ];
      };
      Service = {
        ExecStart = "${pkgs.llama-cpp}/bin/llama-server -m ${modelPath} --alias micro-local --host 127.0.0.1 --port 9931 --cors-origins localhost --ctx-size 4096 --parallel 1 --threads 4 --threads-batch 4 --no-webui";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Baixa modelos na ativacao (idempotente; falha de rede so avisa).
    home.activation.downloadLlamaModels = lib.mkIf cfg.autoDownloadModels (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${downloadModels}/bin/download-llama-models || \
          echo "AVISO: falha ao baixar modelos (sem internet?). Rode depois: download-llama-models"
      ''
    );
  };
}