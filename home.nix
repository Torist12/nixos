{ config, pkgs, ... }:

{
  home.username = "will";
  home.homeDirectory = "/home/will";
  home.stateVersion = "24.11";

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true; # útil pra alguns plugins
    withRuby = false;
    withPython3 = false;

    extraPackages = with pkgs; [
      clang-tools   # clangd (LSP) + clang-format
      cmake
      gdb
      ripgrep       # dependência do telescope (live_grep)
      fd            # dependência do telescope (find_files)
    ];

    plugins = with pkgs.vimPlugins; [
      nvim-lspconfig
      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      luasnip
      cmp_luasnip
      (nvim-treesitter.withPlugins (p: [ p.cpp p.c p.lua p.nix ]))
      telescope-nvim
      plenary-nvim
    ];

    initLua = ''
      -- Treesitter (API nova/nativa, sem depender de nvim-treesitter.configs)
      vim.api.nvim_create_autocmd('FileType', {
        pattern = { 'cpp', 'c', 'lua', 'nix' },
        callback = function()
          vim.treesitter.start()
          vim.wo.foldmethod = 'expr'
          vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
        end,
      })

      -- LSP: clangd para C/C++
          vim.lsp.config('clangd', {})
          vim.lsp.enable('clangd')

      vim.g.llama_config = {
        endpoint_fim = 'http://127.0.0.1:9931/infill',
        endpoint_inst = 'http://127.0.0.1:9931/v1/chat/completions',
        auto_fim = true,
        fim_debounce_ms = 700,
        n_predict = 64,
        ring_n_chunks = 4,
        ring_chunk_size = 32,
        show_info = 1,
      }
      vim.cmd.packadd('llama.vim')

      local aiEnabled = true
      local chatHistory = {}
      local chatBuffer = nil
      local chatJob = nil
      local chatRequestGeneration = 0

      local function toggleAI()
        vim.fn['llama#toggle']()
        aiEnabled = not aiEnabled
        chatRequestGeneration = chatRequestGeneration + 1
        if chatJob then
          vim.fn.jobstop(chatJob)
          chatJob = nil
        end
        if not aiEnabled then
          vim.fn['llama#fim_hide']()
        end

        local state = aiEnabled and 'online' or 'off'
        vim.api.nvim_echo({ { 'IA local: ' .. state, 'MoreMsg' } }, false, {})
      end

      local aiStatusGeneration = 0
      vim.keymap.set({ 'n', 'i' }, '<F4>', function()
        toggleAI()
        aiStatusGeneration = aiStatusGeneration + 1
        local generation = aiStatusGeneration
        vim.defer_fn(function()
          if generation == aiStatusGeneration then
            vim.api.nvim_echo({ { "" } }, false, {})
          end
        end, 10000)
      end, { desc = 'Ativar ou desativar IA local' })

      local function setChatResponse(line, text)
        if chatBuffer and vim.api.nvim_buf_is_valid(chatBuffer) then
          vim.api.nvim_buf_set_lines(chatBuffer, line, line + 1, false, vim.split(text, '\n', { plain = true }))
        end
      end

      local function sendChatMessage(prompt)
        if prompt == nil or prompt:match('^%s*$') then
          return
        end
        if not aiEnabled then
          vim.notify('IA local desativada. Pressione F4 para reativar.', vim.log.levels.WARN)
          return
        end
        if chatJob then
          vim.notify('Aguarde a resposta atual do chat.', vim.log.levels.WARN)
          return
        end

        if not chatBuffer or not vim.api.nvim_buf_is_valid(chatBuffer) then
          vim.cmd('botright 12new')
          chatBuffer = vim.api.nvim_get_current_buf()
          pcall(vim.api.nvim_buf_set_name, chatBuffer, 'llama-chat')
          vim.bo[chatBuffer].buftype = 'nofile'
          vim.bo[chatBuffer].bufhidden = 'hide'
          vim.bo[chatBuffer].swapfile = false
        else
          local chatWindow = vim.fn.bufwinid(chatBuffer)
          if chatWindow == -1 then
            vim.cmd('botright 12split')
            vim.api.nvim_win_set_buf(0, chatBuffer)
          else
            vim.api.nvim_set_current_win(chatWindow)
          end
        end

        local responseLine = vim.api.nvim_buf_line_count(chatBuffer) + 1
        vim.api.nvim_buf_set_lines(chatBuffer, -1, -1, false, {
          'Você: ' .. prompt,
          'IA: [gerando resposta...]',
          "",
        })
        vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(chatBuffer), 0 })

        local messages = vim.deepcopy(chatHistory)
        table.insert(messages, { role = 'user', content = prompt })
        local payload = vim.json.encode({
          model = 'micro-local',
          messages = messages,
          max_tokens = 512,
          temperature = 0.3,
          stream = false,
        })
        local stdout = {}
        local stderr = {}
        chatRequestGeneration = chatRequestGeneration + 1
        local requestGeneration = chatRequestGeneration
        chatJob = vim.fn.jobstart({
          'curl', '--fail', '--silent', '--show-error', '--max-time', '120',
          '-H', 'Content-Type: application/json',
          '--data-binary', payload,
          vim.g.llama_config.endpoint_inst,
        }, {
          stdout_buffered = true,
          stderr_buffered = true,
          on_stdout = function(_, data)
            stdout = data
          end,
          on_stderr = function(_, data)
            stderr = data
          end,
          on_exit = function(_, exitCode)
            vim.schedule(function()
              if requestGeneration ~= chatRequestGeneration then
                return
              end
              chatJob = nil
              if exitCode ~= 0 then
                setChatResponse(responseLine, 'IA: erro: ' .. table.concat(stderr, '\n'))
                return
              end

              local ok, response = pcall(vim.json.decode, table.concat(stdout, '\n'))
              local answer = ok and response.choices
                and response.choices[1]
                and response.choices[1].message
                and response.choices[1].message.content
              if not answer then
                setChatResponse(responseLine, 'IA: resposta inválida do servidor local.')
                return
              end

              table.insert(chatHistory, { role = 'user', content = prompt })
              table.insert(chatHistory, { role = 'assistant', content = answer })
              setChatResponse(responseLine, 'IA: ' .. answer)
            end)
          end,
        })
        if chatJob <= 0 then
          chatJob = nil
          setChatResponse(responseLine, 'IA: não foi possível iniciar o curl.')
        end
      end

      vim.api.nvim_create_user_command('LlamaChat', function(command)
        if not aiEnabled then
          vim.notify('IA local desativada. Pressione F4 para reativar.', vim.log.levels.WARN)
          return
        end
        local prompt = table.concat(command.fargs, ' ')
        if prompt ~= "" then
          sendChatMessage(prompt)
          return
        end
        vim.ui.input({ prompt = 'Você: ' }, sendChatMessage)
      end, { nargs = '*', desc = 'Conversar com a IA local' })
      vim.keymap.set('n', '<F8>', '<Cmd>LlamaChat<CR>', { desc = 'Abrir chat da IA local' })
      vim.api.nvim_create_user_command('LlamaToggleAI', toggleAI, { desc = 'Ativar ou desativar a IA local' })

      -- Autocomplete
      local cmp = require('cmp')
      cmp.setup({
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ['<Tab>'] = cmp.mapping.select_next_item(),
          ['<S-Tab>'] = cmp.mapping.select_prev_item(),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
        }, {
          { name = 'buffer' },
          { name = 'path' },
        }),
      })

      -- Telescope keymaps
      vim.keymap.set('n', '<leader>ff', require('telescope.builtin').find_files, {})
      vim.keymap.set('n', '<leader>fg', require('telescope.builtin').live_grep, {})
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "[](fg:#5277C3) [$directory](fg:#7EBAE4)$git_branch [$user](fg:#A6E3A1) >";
      directory = {
        format = "$path";
        truncation_length = 2;
        truncation_symbol = "…/";
      };
      git_branch = {
        format = " [ $branch](fg:#F9E2AF)";
      };
      username = {
        show_always = true;
        format = "$user";
      };
      character = {
        success_symbol = "";
        error_symbol = "";
      };
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ll = "ls -la";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#konqi";
      update = "cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake /etc/nixos#konqi && cd -";
      nixcode = "code /etc/nixos";
      nixgarbage = "sudo nix-collect-garbage -d";
    };
  };

  programs.kitty = {
    enable = true;
    settings = {
      font_family = "JetBrainsMono Nerd Font";
      font_size = 12;
    };
  };

programs.micro = {
  enable = true;
  settings = {
    colorscheme = "monokai";
    tabsize = 4;
    tabstospaces = true;
    autoindent = true;
    syntax = true;
    ruler = true;
    softwrap = false;
    scrollbar = true;
    statusline = true;
    mouse = true;
    clipboard = "external";

    # LSP
    "lsp.server" = "c++=clangd,c=clangd,python=pyright-langserver --stdio,sh=bash-language-server start,rust=rust-analyzer";
    "lsp.formatOnSave" = true;
    "lsp.autocomplete" = true;
    "lsp.diagnostics" = true;
  };
};
  programs.tmux = {
  enable = true;
  extraConfig = builtins.readFile ./tmux.conf;
};

  home.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ];

  imports = [
    ./llama-cpp-nvim.nix
  ];

  programs.llama-cpp-nvim.enable = true;
  
}