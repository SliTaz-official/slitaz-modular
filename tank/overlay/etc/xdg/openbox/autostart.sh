# This shell script is run before Openbox launches.
# Environment variables set here are passed to the Openbox session.

# DBUS message bus (automount removable devices)
dbus-launch --exit-with-session &

# Handle Hal events with Ivman (notification with desktopbox).
#ivman &

# Start PCmanFM as daemon for Wallpaper and desktop icons.
pcmanfm -d &

# Start the Freedesktop panel standard menu.
lxpanel &

# Packages update notification
tazpkg-notify &

# Start Parcellite clipboard manager.
#parcellite &

# Launch Xpad desktop notes utility.
#xpad &

# Desktop effects composer.
#xcompmgr -c -r 10 &

# Set a background image using hsetroot (depends on imlib2).
#hsetroot -fill /usr/share/images/slitaz-background.png &

# Background color with xsetroot.
#xsetroot -solid "#222222" &

# Wbar2 icon bar
#$(sleep 3 && wbar) &
