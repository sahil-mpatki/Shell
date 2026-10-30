/* ShellOS dwm configuration. Same core keys as ShellOS's Hyprland, i3 and bspwm:
 *   Super+Return terminal      Super+D apps            Super+Q close
 *   Super+1..9 tag             Super+Shift+1..9 move   Super+F monocle
 *   Super+Space float          Super+J/K focus         Super+H/L master size
 *   Super+Escape lock          Super+Shift+E exit      Print screenshot
 * dwm has no directional focus or fullscreen toggle; J/K cycle the stack and
 * Super+F switches to the monocle layout. */
#include <X11/XF86keysym.h>

/* appearance */
static const unsigned int borderpx  = 2;
static const unsigned int snap      = 32;
static const int showbar            = 1;
static const int topbar             = 1;
static const char *fonts[]          = { "JetBrains Mono:size=10", "FontAwesome:size=10" };
static const char bg[]              = "#0B1416";
static const char surface[]         = "#14201F";
static const char fg[]              = "#E6F4F2";
static const char muted[]           = "#6B8783";
static const char accent[]          = "#2EC4B6";
static const char *colors[][3]      = {
	/*               fg     bg      border */
	[SchemeNorm] = { muted, bg,     surface },
	[SchemeSel]  = { bg,    accent, accent  },
};

/* tagging */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

static const Rule rules[] = {
	/* class                         instance  title  tags mask  isfloating  monitor */
	{ "Pavucontrol",                 NULL,     NULL,  0,         1,          -1 },
	{ "org.pulseaudio.pavucontrol",  NULL,     NULL,  0,         1,          -1 },
	{ "Nm-connection-editor",        NULL,     NULL,  0,         1,          -1 },
};

/* layout(s) */
static const float mfact     = 0.55;
static const int nmaster     = 1;
static const int resizehints = 0;
static const int lockfullscreen = 1;

static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "[]=",      tile },
	{ "><>",      NULL },
	{ "[M]",      monocle },
};

/* key definitions */
#define MODKEY Mod4Mask
#define TAGKEYS(KEY,TAG) \
	{ MODKEY,                       KEY,      view,           {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask,           KEY,      toggleview,     {.ui = 1 << TAG} }, \
	{ MODKEY|ShiftMask,             KEY,      tag,            {.ui = 1 << TAG} }, \
	{ MODKEY|ControlMask|ShiftMask, KEY,      toggletag,      {.ui = 1 << TAG} },

#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* commands (dmenumon is required by dwm's spawn()) */
static char dmenumon[2] = "0";
static const char *dmenucmd[] = { "rofi", "-show", "drun", NULL };
static const char *termcmd[]  = { "alacritty", NULL };

static const Key keys[] = {
	/* modifier                     key                       function        argument */
	{ MODKEY,                       XK_Return,                spawn,          {.v = termcmd } },
	{ MODKEY,                       XK_d,                     spawn,          {.v = dmenucmd } },
	{ MODKEY,                       XK_b,                     spawn,          SHCMD("firefox") },
	{ MODKEY,                       XK_q,                     killclient,     {0} },
	{ MODKEY,                       XK_Escape,                spawn,          SHCMD("shellos-lock") },
	{ MODKEY|ShiftMask,             XK_e,                     quit,           {0} },
	{ 0,                            XK_Print,                 spawn,          SHCMD("maim -s | xclip -selection clipboard -t image/png") },
	{ ShiftMask,                    XK_Print,                 spawn,          SHCMD("mkdir -p ~/Pictures && maim ~/Pictures/screenshot-$(date +%F-%H%M%S).png") },
	{ MODKEY|ShiftMask,             XK_b,                     togglebar,      {0} },
	{ MODKEY,                       XK_j,                     focusstack,     {.i = +1 } },
	{ MODKEY,                       XK_k,                     focusstack,     {.i = -1 } },
	{ MODKEY,                       XK_i,                     incnmaster,     {.i = +1 } },
	{ MODKEY,                       XK_o,                     incnmaster,     {.i = -1 } },
	{ MODKEY,                       XK_h,                     setmfact,       {.f = -0.05} },
	{ MODKEY,                       XK_l,                     setmfact,       {.f = +0.05} },
	{ MODKEY|ShiftMask,             XK_Return,                zoom,           {0} },
	{ MODKEY,                       XK_Tab,                   view,           {0} },
	{ MODKEY,                       XK_t,                     setlayout,      {.v = &layouts[0]} },
	{ MODKEY|ShiftMask,             XK_f,                     setlayout,      {.v = &layouts[1]} },
	{ MODKEY,                       XK_f,                     setlayout,      {.v = &layouts[2]} },
	{ MODKEY,                       XK_space,                 togglefloating, {0} },
	{ MODKEY,                       XK_0,                     view,           {.ui = ~0 } },
	{ MODKEY|ShiftMask,             XK_0,                     tag,            {.ui = ~0 } },
	{ MODKEY,                       XK_comma,                 focusmon,       {.i = -1 } },
	{ MODKEY,                       XK_period,                focusmon,       {.i = +1 } },
	{ MODKEY|ShiftMask,             XK_comma,                 tagmon,         {.i = -1 } },
	{ MODKEY|ShiftMask,             XK_period,                tagmon,         {.i = +1 } },
	{ 0,                            XF86XK_AudioRaiseVolume,  spawn,          SHCMD("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+") },
	{ 0,                            XF86XK_AudioLowerVolume,  spawn,          SHCMD("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") },
	{ 0,                            XF86XK_AudioMute,         spawn,          SHCMD("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") },
	{ 0,                            XF86XK_AudioPlay,         spawn,          SHCMD("playerctl play-pause") },
	{ 0,                            XF86XK_AudioNext,         spawn,          SHCMD("playerctl next") },
	{ 0,                            XF86XK_AudioPrev,         spawn,          SHCMD("playerctl previous") },
	{ 0,                            XF86XK_MonBrightnessUp,   spawn,          SHCMD("brightnessctl set 5%+") },
	{ 0,                            XF86XK_MonBrightnessDown, spawn,          SHCMD("brightnessctl set 5%-") },
	TAGKEYS(                        XK_1,                      0)
	TAGKEYS(                        XK_2,                      1)
	TAGKEYS(                        XK_3,                      2)
	TAGKEYS(                        XK_4,                      3)
	TAGKEYS(                        XK_5,                      4)
	TAGKEYS(                        XK_6,                      5)
	TAGKEYS(                        XK_7,                      6)
	TAGKEYS(                        XK_8,                      7)
	TAGKEYS(                        XK_9,                      8)
};

/* button definitions */
static const Button buttons[] = {
	/* click                event mask      button          function        argument */
	{ ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
	{ ClkLtSymbol,          0,              Button3,        setlayout,      {.v = &layouts[2]} },
	{ ClkWinTitle,          0,              Button2,        zoom,           {0} },
	{ ClkStatusText,        0,              Button2,        spawn,          {.v = termcmd } },
	{ ClkClientWin,         MODKEY,         Button1,        movemouse,      {0} },
	{ ClkClientWin,         MODKEY,         Button2,        togglefloating, {0} },
	{ ClkClientWin,         MODKEY,         Button3,        resizemouse,    {0} },
	{ ClkTagBar,            0,              Button1,        view,           {0} },
	{ ClkTagBar,            0,              Button3,        toggleview,     {0} },
	{ ClkTagBar,            MODKEY,         Button1,        tag,            {0} },
	{ ClkTagBar,            MODKEY,         Button3,        toggletag,      {0} },
};
