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
  fonts.packages = [ pkgs.geist-font pkgs.noto-fonts-color-emoji ];   # (emoji: the picker, the launcher's :emoji)
  services.accounts-daemon.enable = true;   # your account picture
  programs.dconf.enable = true;             # so theme settings (gsettings) stick
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];   # Flatpak and Snap apps: light or dark
  # Printing and scanning (Settings → Printers & Scanners)
  services.printing.enable = true;
  services.avahi = { enable = true; nssmdns4 = true; };   # finds network printers
  hardware.sane = { enable = true; extraBackends = [ pkgs.sane-airscan ]; };
  environment.systemPackages = with pkgs; [
    quickshell qt6.qtdeclarative qt6.qtsvg qt6Packages.qt6ct
    qt6.qtmultimedia   # optional: click sound, and sounds without a delay
    # (python's modules have to come with it to be found: a separate package isn't on its path)
    (python3.withPackages (ps: [ ps.pillow ps.numpy ps.pygobject3 ]))   # pygobject3: the tray's register
    librsvg imagemagick wl-clipboard libnotify curl unzip xdg-utils xdg-user-dirs
    diffutils   # cmp: is the installed copy (Slate, the login screen) up to date
    glib gsettings-desktop-schemas fontconfig   # gio / gsettings / gdbus, and fc-list (font lists)
    hyprland-guiutils btop ffmpeg pciutils      # optional extras
    grim slurp hyprpicker brightnessctl adw-gtk3 papirus-icon-theme
    system-config-printer simple-scan   # printer settings, and scanning
    v4l-utils   # Settings → Webcam: the camera's picture settings (v4l2-ctl)
    # Optional: Hyprbars title bars instead of Slate's own. Nix builds the plugin; link it where Slate looks, e.g.
    #   ln -s ${pkgs.hyprlandPlugins.hyprbars}/lib/libhyprbars.so ~/.local/share/slate/plugins/hyprbars.so
    hyprlandPlugins.hyprbars
  ];
  # Optional: Slate's login screen runs on greetd
  # services.greetd.enable = true;
}
