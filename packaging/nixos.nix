# Slate on NixOS (unstable: Hyprland 0.57+ and Quickshell 0.3+). Add to configuration.nix,
# run `sudo nixos-rebuild switch`, then in the Slate folder: ./install.sh --no-deps
{ pkgs, ... }: {
  programs.hyprland = { enable = true; withUWSM = true; };
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  security.polkit.enable = true;
  services.pipewire = { enable = true; pulse.enable = true; wireplumber.enable = true; };
  fonts.packages = [ pkgs.geist-font ];
  environment.systemPackages = with pkgs; [
    quickshell qt6.qtdeclarative qt6.qtsvg qt6Packages.qt6ct
    qt6.qtmultimedia   # optional: click sound, and sounds without a delay
    python3 python3Packages.pillow python3Packages.numpy librsvg imagemagick wl-clipboard libnotify curl unzip xdg-utils
    grim slurp hyprpicker brightnessctl adw-gtk3 papirus-icon-theme
    # Title bars in floating mode: Nix builds the plugin; link it where Slate looks, e.g.
    #   ln -s ${pkgs.hyprlandPlugins.hyprbars}/lib/libhyprbars.so ~/.local/share/slate/plugins/hyprbars.so
    hyprlandPlugins.hyprbars
  ];
  # Optional: Slate's login screen runs on greetd
  # services.greetd.enable = true;
}
