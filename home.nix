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

  home.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ];
}