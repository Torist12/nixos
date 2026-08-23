{ config, pkgs, ... }:

{
  home.username = "will";
  home.homeDirectory = "/home/will";
  home.stateVersion = "24.11";

programs.starship = {
  enable = true;
  settings = {
    add_newline = false;
    format = "[](fg:#5277C3) [$directory](fg:#7EBAE4)$git_branch [$user](fg:#A6E3A1) >";
    
    directory = {
      format = "$path";
      truncation_length = 2;
      truncation_symbol = "…/";
    };
    
    git_branch = {
      format = " [ $branch](fg:#F9E2AF)";
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
