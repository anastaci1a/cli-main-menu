#!/usr/bin/env bash
# Tracked defaults, loaded before the optional, ignored config.bash.
# Copy this file to config.bash for personal settings, then source ~/.bashrc.
EZ_MENU_TITLE='MAIN MENU'
EZ_MENU_ANIMATE_STARS=1
EZ_MENU_TWINKLE_ADVANCE_MS=500  # positive values move the probability cycle earlier
EZ_MENU_TWINKLE_RATE_PERCENT=250 # 100 = original rate; 250 = 2.5x
EZ_MENU_HORIZON_DENSITY_PERCENT=600 # bottom density vs top; 100 = flat, max 800
EZ_MENU_SWEEP_INTERVAL_MS=4000
EZ_MENU_SWEEP_DURATION_MS=1467 # longer edge easing, same peak speed as the old 1 s sweep
EZ_MENU_SWEEP_HUE_STEP=70
EZ_MENU_STAR_SATURATION_MAX=800 # thousandths: 800 = 80%
EZ_MENU_STAR_HUE_SPREAD=60      # total range, centered with a Gaussian-like distribution
EZ_MENU_SWEEP_ACCENT_OFFSET=180 # title/markers opposite the star palette's center

# Colors from theme.bash can also be overridden in config.bash. For example:
# C_PINK=$'\033[38;5;177m'
# C_STAR_BLUE=$'\033[38;5;103m'
# C_STAR_LAVENDER=$'\033[38;5;146m'
# C_STAR_PINK=$'\033[38;5;139m'
