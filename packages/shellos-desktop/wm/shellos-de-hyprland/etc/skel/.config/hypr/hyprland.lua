-- ShellOS Hyprland configuration (Hyprland 0.55+, Lua).
-- Same core keys as ShellOS's i3, bspwm and dwm:
--   Super+Return terminal    Super+D apps           Super+Q close
--   Super+1..9 workspace     Super+Shift+1..9 move  Super+F fullscreen
--   Super+Space float        Super+H/J/K/L focus    Super+Shift+H/J/K/L move
--   Super+Escape lock        Super+Shift+E exit     Print screenshot
-- Reference: https://wiki.hypr.land/Configuring/

local terminal = "alacritty"
local menu     = "fuzzel"
local mainMod  = "SUPER"

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

hl.on("hyprland.start", function ()
    hl.exec_cmd("swaybg -m fill -i /usr/share/backgrounds/shellos/shellos-spiral.png")
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
end)

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,
        col = {
            active_border   = { colors = {"rgba(2ec4b6ff)", "rgba(1a7f76ff)"}, angle = 45 },
            inactive_border = "rgba(14201faa)",
        },
        layout = "dwindle",
    },
    decoration = {
        rounding = 8,
        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 3,
            color        = 0xaa050809,
        },
        blur = {
            enabled = true,
            size    = 4,
            passes  = 2,
        },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        touchpad = { natural_scroll = true },
    },
})

hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.animation({ leaf = "global",     enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "easeOutQuint", style = "popin 90%" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "easeOutQuint", style = "fade" })

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.bind(mainMod .. " + Return",      hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + D",           hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + B",           hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + Q",           hl.dsp.window.close())
hl.bind(mainMod .. " + Escape",      hl.dsp.exec_cmd("loginctl lock-session"))
hl.bind(mainMod .. " + SHIFT + E",   hl.dsp.exit())
hl.bind(mainMod .. " + F",           hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + Space",       hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + V",           hl.dsp.layout("togglesplit"))
hl.bind("Print",                     hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy --type image/png"))
hl.bind("SHIFT + Print",             hl.dsp.exec_cmd("mkdir -p ~/Pictures && grim ~/Pictures/screenshot-$(date +%F-%H%M%S).png"))

local dirs = { h = "left", j = "down", k = "up", l = "right",
               left = "left", down = "down", up = "up", right = "right" }
for key, dir in pairs(dirs) do
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ direction = dir }))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ direction = dir }))
end

for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i,               hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i,       hl.dsp.window.move({ workspace = i }))
end
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse:272",  hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273",  hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"),                            { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"),                            { locked = true, repeating = true })
hl.bind("XF86AudioPlay",         hl.dsp.exec_cmd("playerctl play-pause"),                             { locked = true })
hl.bind("XF86AudioNext",         hl.dsp.exec_cmd("playerctl next"),                                   { locked = true })
hl.bind("XF86AudioPrev",         hl.dsp.exec_cmd("playerctl previous"),                               { locked = true })

hl.window_rule({ name = "float-mixer", match = { class = "org.pulseaudio.pavucontrol" }, float = true })
