[[ -f ~/.bashrc ]] && source ~/.bashrc

# Auto-startx on tty1 (login already handled by getty autologin).
if [[ -z "${DISPLAY:-}" ]] && [[ "$(tty)" = "/dev/tty1" ]]; then
    exec startx 2>~/.xsession-errors
fi
