---
name: nixos-konqi
description: "Contexto prático do NixOS konqi para IAs que precisam entender, diagnosticar ou alterar esta configuração."
---

# Skill: NixOS konqi

## Objetivo

Use este documento como contexto rápido antes de responder ou alterar este repositório. Ele descreve a configuração declarativa do computador `konqi` e a integração de IA local. Confirme sempre os arquivos atuais antes de assumir que este resumo continua atualizado.

## Visão geral

Este repositório configura um computador NixOS `x86_64-linux`, com o host `konqi`, usando Nix Flakes e Home Manager integrado ao rebuild do sistema.

```text
flake.nix
  -> configuration.nix (sistema, serviços e pacotes globais)
  -> Home Manager
       -> home.nix (programas e preferências do usuário will)
       -> llama-cpp-nvim.nix (IA local para editores e terminal)
```

A fonte de verdade é a configuração versionada em `/etc/nixos`. Mudanças declarativas só passam a valer depois de avaliar e aplicar a configuração.

## Arquivos e responsabilidades

- `flake.nix`: define as entradas `nixpkgs` e `home-manager` e a saída `nixosConfigurations.konqi`. A arquitetura é `x86_64-linux`.
- `flake.lock`: fixa as revisões das entradas. Atualize-o quando uma atualização de flake for intencional.
- `configuration.nix`: opções do sistema, ambiente gráfico, hardware habilitado, usuário, serviços e pacotes globais.
- `hardware-configuration.nix`: configuração gerada de discos e hardware. Não edite manualmente sem necessidade; mudanças de hardware normalmente pedem regeneração.
- `home.nix`: ambiente do usuário `will`, Neovim, Micro, Zsh, Starship, Kitty, tmux e habilitação do módulo de IA.
- `llama-cpp-nvim.nix`: módulo Home Manager que prepara llama.cpp, servidor, modelo, plugin do Micro, plugin do Neovim e comando de chat `nixai`.
- `micro-llama.lua`: cliente Lua do Micro para pedir sugestões e conversar com o servidor.
- `micro-llama-repo.json`: metadados do plugin Lua do Micro.
- `tmux.conf`: configuração do tmux lida por `home.nix`.
- `README.md`: documentação extensa do repositório; confira os arquivos de configuração quando houver divergência.

No flake, Home Manager usa o mesmo `nixpkgs` (`useGlobalPkgs = true`), instala pacotes via usuário (`useUserPackages = true`) e salva backups com extensão `.hm-backup`. O módulo de Home Manager aplica `home.nix` para `will` durante o mesmo `nixos-rebuild`.

## Como aplicar mudanças

O alias `rebuild` em `home.nix` executa:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#konqi
```

Para atualizar as entradas do flake, o alias `update` executa `nix flake update` e depois aplica o rebuild. Isso pode mudar dependências fixadas; revise o diff de `flake.lock` antes de considerar a atualização concluída.

Fluxo recomendado para uma alteração:

1. Identifique se a opção pertence ao sistema (`configuration.nix`) ou ao usuário (`home.nix`/módulo importado).
2. Leia o bloco completo que controla a opção e verifique se já existe uma implementação próxima.
3. Faça a menor mudança declarativa possível.
4. Valide a avaliação/build, preferencialmente com `sudo nixos-rebuild dry-build --flake /etc/nixos#konqi`.
5. Aplique com `sudo nixos-rebuild switch --flake /etc/nixos#konqi` somente quando for apropriado.

Não altere `system.stateVersion` ou `home.stateVersion` como se fossem versões do sistema a atualizar: são valores de compatibilidade e precisam de uma justificativa específica.

## Sistema

Detalhes declarados em `configuration.nix`:

- Nix usa `nix-command` e `flakes`; pacotes não livres são permitidos.
- Fontconfig habilitado para descoberta de fontes.
- Boot EFI com systemd-boot, limite de quatro configurações no menu e kernel `linuxPackages_latest`.
- Garbage collector automático semanal, removendo gerações com mais de 30 dias.
- Host `konqi`, Wi-Fi habilitado e NetworkManager ativo.
- Locale `pt_BR.UTF-8`, fuso `America/Sao_Paulo`, teclado X11 `br`/`thinkpad` e console `br-abnt2`.
- X11, KDE Plasma 6 e SDDM habilitados.
- Impressão via CUPS; áudio via PipeWire (ALSA, compatibilidade 32-bit e PulseAudio); PulseAudio legado desabilitado; `rtkit` habilitado.
- Leitor de impressão digital habilitado para `sudo`, login e SDDM.
- Gráficos habilitados com suporte 32-bit; Steam habilitado e com portas de Remote Play e servidor dedicado abertas no firewall.
- Libvirt e virt-manager; Podman com compatibilidade Docker; não há daemon Docker declarado. Suporte AppImage habilitado com binfmt.
- Firefox, Tailscale, OpenSSH, `mtr` e agente GnuPG com suporte a SSH habilitados.
- Usuário normal `will`, shell Zsh, grupos `networkmanager`, `wheel`, `libvirtd`, `dialout`, `docker`, `video`, `audio`, `input`, `kvm` e `users`; Kate é instalado para esse usuário.

`hardware-configuration.nix` foi gerado pelo NixOS: declara a raiz ext4, `/boot` EFI em VFAT, sem swap, módulos de initrd para USB/NVMe/SD, KVM Intel e microcode Intel condicional. Ele também fixa a plataforma `x86_64-linux`. Não copie identificadores de disco para documentação; edite ou regenere esse arquivo apenas quando a mudança for realmente de hardware/armazenamento.

Pacotes em `environment.systemPackages` (disponíveis globalmente): `wget`, `git`, `curl`, `vim`, `neovim`, `fastfetch`, `vscode.fhs`, `tmux`, `libreoffice`, `kitty`, `starship`, `zsh`, `btop`, `cmatrix`, `cbonsai`, `nodejs_22`, `python3`, `gcc`, `postman`, `podman`, `distrobox`, `dbeaver-bin`, `bun`, `rustup`, `cargo-watch`, `eza`, `bat`, `fzf`, `ripgrep`, `zoxide`, `lazygit`, `gh`, `nasm`, `gdb`, `steam-run`, `emacs`, `wireguard-tools`, `qbittorrent`, `micro` e `clang-tools`.

Não confunda `system.stateVersion = "26.05"` com a versão corrente do NixOS: é o valor de compatibilidade da instalação. O Home Manager usa `home.stateVersion = "24.11"`; mantenha ambos sem alteração, salvo migração intencional e documentada.

## Home Manager e ferramentas

O flake integra Home Manager como módulo do NixOS, usando os pacotes globais e instalando os pacotes do usuário. O `home.nix` configura o usuário `will` em `/home/will`; backups de arquivos substituídos recebem a extensão `.hm-backup`.

- **Zsh:** autosuggestions e syntax highlighting. Aliases: `ll` (`ls -la`), `rebuild` (switch do flake `konqi`), `update` (atualiza o flake e aplica switch), `nixcode` (abre `/etc/nixos` no VS Code) e `nixgarbage` (coleta garbage do Nix).
- **Starship:** prompt com diretório, branch Git e usuário; sem linha adicional.
- **Kitty:** fonte JetBrainsMono Nerd Font, tamanho 12. Home Manager também instala JetBrains Mono Nerd Font e Symbols Only.
- **tmux:** configuração em `tmux.conf`; prefixo `Ctrl+A`, mouse habilitado, histórico de 10000 linhas, índices começando em 1, splits `|` e `-`, navegação de painéis `h/j/k/l`, mover painel com `H/J/K/L`, resize mode com `R`, zoom com `prefix+f`, nova janela com `Enter` ou `c`, fechar painel/janela com `x`/`X` e recarregar com `prefix+r`. `Alt+Left`/`Alt+Right` alternam janelas. Layouts: `prefix+e` horizontal, `prefix+E` vertical, `prefix+t` tiled, `prefix+m` main-vertical. A barra mostra sessão, título do painel, data/hora e janelas.

## Editores

### Neovim

O Home Manager habilita aliases `vi` e `vim`, Node.js, mas não Ruby nem Python no wrapper do Neovim, e plugins `nvim-lspconfig`, `nvim-cmp`, `cmp-nvim-lsp`, `cmp-buffer`, `cmp-path`, `LuaSnip`, `cmp_luasnip`, Telescope, Plenary e Treesitter. Treesitter inclui parsers C, C++, Lua e Nix; o autocmd ativa highlight e folding nesses tipos. O LSP configurado diretamente no `initLua` é `clangd` para C/C++.

Pacotes extras do wrapper Neovim: `clang-tools`, `cmake`, `gdb`, `ripgrep` e `fd`. `nvim-cmp` usa fontes LSP, snippets, buffer e caminho; `Ctrl+Space` abre completion, `Enter` confirma, `Tab`/`Shift+Tab` navegam. Telescope: `<leader>ff` busca arquivos e `<leader>fg` pesquisa texto.

O plugin `llama.vim` é instalado pelo módulo de IA, mas carregado/configurado no `initLua` de `home.nix`. Não trate a opção de IA do Neovim como controle do serviço systemd compartilhado.

### Micro e servidores LSP

O Micro usa tema `monokai`, tabulação de quatro espaços, autoindent, régua, barra de status, mouse e clipboard externo; soft wrap está desligado. As opções LSP habilitam autocomplete, diagnósticos e formatação ao salvar.

`lsp.server` declara `clangd` para C/C++, `pyright-langserver --stdio` para Python, `bash-language-server start` para shell e `rust-analyzer` para Rust. **Estado real dos pacotes:** `clang-tools` consta em `environment.systemPackages`; `pyright`, `bash-language-server` e `rust-analyzer` não constam nas listas atuais deste repositório. Se essas linguagens precisarem de LSP funcional, confirme se os executáveis estão no PATH e declare os pacotes apropriados na configuração. As opções do Micro não instalam automaticamente o plugin `lsp`; a documentação existente orienta instalá-lo com `micro -plugin install lsp`.

No plugin de IA do Micro, `F4` pede conclusão imediata e `F8` abre `llama-chat`; `Tab` só consome a sugestão de IA válida e, sem ela, tenta os comandos padrão de autocomplete/indentação.

## IA local: arquitetura

O módulo `llama-cpp-nvim.nix` é importado e habilitado no fim de `home.nix`. Ele instala `llama.cpp`, prepara o plugin `llama.vim`, instala o plugin Lua para Micro e define o serviço systemd de usuário `llama-micro-server`.

O serviço carrega um modelo GGUF Qwen2.5-Coder 1.5B Q8_0 e escuta apenas em `127.0.0.1:9931`. Micro, Neovim e `nixai` usam esse servidor compartilhado. O modelo fica em:

```text
~/.local/share/llama-cpp/models/qwen2.5-coder-1.5b-q8_0.gguf
```

Na primeira ativação, o Home Manager tenta baixar o modelo (cerca de 1,6 GB); é necessário ter internet. Depois do download, a inferência funciona localmente. O serviço usa CPU e limita o processamento a quatro threads. Não presuma aceleração por GPU.

`programs.llama-cpp-nvim.autoDownloadModels` fica habilitado por padrão. O download é idempotente e retoma arquivo parcial; falha de rede gera um aviso sem impedir toda a ativação. Para tentar novamente manualmente, execute `download-llama-models` no ambiente do usuário. O `llama.vim` é fixado no commit `e1ca1cc6af9da73f4ae21f810f33909d515592e6` via `pkgs.fetchFromGitHub`.

Parâmetros do serviço systemd de usuário: alias do modelo `micro-local`, host `127.0.0.1`, porta `9931`, CORS `localhost`, contexto 4096, uma solicitação paralela, quatro threads normais e de batch, sem Web UI; reinicia em falha após cinco segundos. O wrapper está em `~/.local/share/llama-cpp/bin/llama-server`, mas o serviço chama diretamente o binário do pacote Nix.

Endpoints usados:

- `POST /completion`: conclusão/FIM usada pelo Micro e pelo plugin Neovim.
- `POST /infill`: endpoint FIM configurado no Neovim; confirme o comportamento com a versão instalada do `llama.vim` antes de alterar.
- `POST /v1/chat/completions`: chat OpenAI-compatível usado pelo Micro, Neovim e `nixai`.
- `GET /health`: verificação simples de saúde do servidor.

### Micro

`micro-llama.lua` envia ao servidor o trecho ao redor do cursor para preenchimento FIM. Após uma pausa de 700 ms, uma sugestão pode ser solicitada automaticamente; `F4` solicita manualmente. A sugestão aparece na barra de informações e `Tab` a insere se o buffer e o cursor ainda corresponderem ao contexto usado no pedido. Pedidos antigos são cancelados ou ignorados quando o texto muda.

O cliente usa até 4000 caracteres antes e depois do cursor; conclusão pede 32 tokens, temperatura 0,1 e resposta não transmitida em streaming. O chat do Micro pede até 192 tokens, temperatura 0,3 e mantém histórico apenas durante a sessão do editor.

`F8` abre o comando `llama-chat`. O chat aparece em uma divisão do editor e conserva o histórico enquanto o Micro estiver aberto. O cliente HTTP é `micro-llama-request`, implementado no módulo com `curl` e `jq`.

### Neovim

O `initLua` em `home.nix` configura o `llama.vim` e o `nvim-cmp`. `F4` alterna a integração de IA local e cancela uma solicitação de chat em andamento ao desativá-la. `F8` e `:LlamaChat` abrem o chat; `:LlamaChat pergunta` envia uma pergunta diretamente. A IA desligada no Neovim não desliga o serviço compartilhado, que continua disponível para os demais clientes.

Parâmetros FIM do Neovim: endpoint configurado `/infill`, debounce de 700 ms, previsão de 64 tokens, janela circular de quatro chunks de 32 tokens e exibição de informações. O chat usa `/v1/chat/completions`, até 512 tokens, temperatura 0,3, timeout curl de 120 segundos e histórico em memória durante a sessão.

### Terminal

O módulo instala `nixai`, um cliente de chat interativo com histórico durante a execução:

```sh
nixai
nixai "Como encontro arquivos grandes?"
```

Use `/sair`, `/exit` ou `/quit` para terminar.

## Diagnóstico da IA local

```sh
systemctl --user status llama-micro-server
curl -fsS http://127.0.0.1:9931/health
```

Se o servidor não responder, confira se o serviço está ativo, se o modelo existe no caminho esperado e se o download da primeira ativação terminou. O cliente precisa de `curl` e `jq`, instalados pelo módulo.

## Regras para IAs que alterarem este repositório

- Leia o arquivo dono da opção antes de editar; não deduza comportamento apenas pelo nome do pacote.
- Preserve a separação entre configuração do sistema e configuração do usuário.
- Mantenha a IA local vinculada ao endereço loopback, salvo solicitação explícita e análise das implicações de segurança. Não exponha o servidor na rede por conveniência.
- Não coloque senhas, tokens, chaves privadas ou outros segredos nos arquivos Nix ou neste documento.
- Não edite o arquivo gerado de hardware para resolver uma opção comum de sistema.
- Não atualize dependências, modelos ou revisões do plugin sem necessidade da tarefa.
- Ao mudar atalhos, endpoints, opções do servidor ou caminhos do modelo, confira todos os clientes que compartilham o serviço e atualize esta documentação.
- Não apague nem sobrescreva alterações preexistentes do usuário. Faça alterações pequenas e valide-as.
