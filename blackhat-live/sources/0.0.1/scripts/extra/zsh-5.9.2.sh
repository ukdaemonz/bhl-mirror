#!/bin/bash

JOBS="${JOBS:-$(nproc)}"
INITIAL_DIR="${INITIAL_DIR:-$(pwd)}"
BHL_VERSION="0.0.1"
ZSH_VERSION="5.9.2"
ZSH_SHA256="36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81"
PUBLIC_INDEX_ADDRESS="${PUBLIC_INDEX_ADDRESS:-77.105.133.52}"

if [[ -v JOBS ]]; then
    if [ "$JOBS" -eq 0 ] 2>/dev/null; then
        echo "MAKEJOBS cannot be '0'"
        echo "Re-run script with example 'JOBS=2 ./zsh-5.9.2.sh'"
        exit 1
    fi
fi

if curl -fsS -m 10 "http://${PUBLIC_INDEX_ADDRESS}/" &>/dev/null; then
    echo "Public index of BlackHat working"
else
    echo "Public index is not working or network is down"
    echo "Run 'sh ~/net-fix.sh' or manually set network up"
    exit 1
fi

mkdir -pv /sources/extra/
cd /sources/extra || exit 1

rm -f "zsh-${ZSH_VERSION}.tar.xz"
if ! wget -c --tries=5 --timeout=20 \
    "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/zsh-${ZSH_VERSION}.tar.xz" 2>/dev/null; then
    if ! wget -c --tries=5 --timeout=20 \
        "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/zsh/zsh-${ZSH_VERSION}.tar.xz" 2>/dev/null; then
        wget -c --tries=10 --timeout=30 \
            "https://www.zsh.org/pub/zsh-${ZSH_VERSION}.tar.xz" || exit 1
    fi
fi

if [[ -f "zsh-${ZSH_VERSION}.tar.xz" ]]; then
    GOT_SHA="$(sha256sum "zsh-${ZSH_VERSION}.tar.xz" | awk '{print $1}')"
    if [ "$GOT_SHA" != "$ZSH_SHA256" ]; then
        echo "Error: sha256 mismatch for zsh-${ZSH_VERSION}.tar.xz ($GOT_SHA)"
        exit 1
    fi

    rm -rf "zsh-${ZSH_VERSION}"
    tar -xf "zsh-${ZSH_VERSION}.tar.xz" && cd "zsh-${ZSH_VERSION}/" || exit 1

    sed -e 's|/etc/z|/etc/zsh/z|g' -i Doc/*.* 2>/dev/null || true
    touch Doc/help.txt Doc/help/* 2>/dev/null || true

    PCRE_FLAG=""
    if command -v pcre2-config >/dev/null 2>&1; then
        PCRE_FLAG="--enable-pcre"
    fi

    if ! (
        ./configure --prefix=/usr \
            --bindir=/bin \
            --sysconfdir=/etc/zsh \
            --enable-etcdir=/etc/zsh \
            --enable-cap \
            --enable-gdbm \
            $PCRE_FLAG
    ); then
        echo "Error: configure failed!"
        exit 1
    fi

    if ! (make -j"$JOBS" && make install); then
        echo "Error: build or installation failed!"
        exit 1
    fi

    if command -v makeinfo >/dev/null 2>&1; then
        make infodir=/usr/share/info install.info 2>/dev/null || true
    fi

    if [ ! -e /usr/bin/zsh ] && [ -x /bin/zsh ]; then
        ln -sfv /bin/zsh /usr/bin/zsh
    elif [ ! -e /bin/zsh ] && [ -x /usr/bin/zsh ]; then
        ln -sfv /usr/bin/zsh /bin/zsh
    fi

    touch /etc/shells
    for s in /bin/bash /usr/bin/bash /bin/zsh /usr/bin/zsh; do
        grep -qxF "$s" /etc/shells 2>/dev/null || echo "$s" >> /etc/shells
    done

    install -vdm755 /etc/zsh /etc/profile.d

    cat > /usr/bin/csh << 'CSH_EOF'
#!/bin/bash

TEMP_ONLY=0
SET_ONLY=0
TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        -t|--temp)
            TEMP_ONLY=1
            shift
            ;;
        --set-only)
            SET_ONLY=1
            shift
            ;;
        -l|--list|list|status)
            CUR_SH="$(basename "${SHELL:-unknown}")"
            DEF_SH="$(awk -F: -v u="${USER:-$(id -un)}" '$1==u {print $7}' /etc/passwd 2>/dev/null)"
            echo "Current shell : ${SHELL:-unknown} ($CUR_SH)"
            echo "Default shell : ${DEF_SH:-unknown}"
            echo "Available     : zsh, bash"
            exit 0
            ;;
        -h|--help|help)
            echo "Usage: csh [zsh|bash] [-t|--temp] [status]"
            exit 0
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    CUR_SH="$(basename "${SHELL:-unknown}")"
    DEF_SH="$(awk -F: -v u="${USER:-$(id -un)}" '$1==u {print $7}' /etc/passwd 2>/dev/null)"
    echo "Current shell : ${SHELL:-unknown} ($CUR_SH)"
    echo "Default shell : ${DEF_SH:-unknown}"
    echo "Usage         : csh zsh | csh bash | csh -t <zsh|bash>"
    exit 0
fi

case "$TARGET" in
    zsh|/bin/zsh|/usr/bin/zsh)
        if [ -x /bin/zsh ]; then
            SHELL_PATH="/bin/zsh"
        elif [ -x /usr/bin/zsh ]; then
            SHELL_PATH="/usr/bin/zsh"
        else
            echo "csh: zsh is not installed" >&2
            exit 1
        fi
        ;;
    bash|/bin/bash|/usr/bin/bash)
        if [ -x /bin/bash ]; then
            SHELL_PATH="/bin/bash"
        elif [ -x /usr/bin/bash ]; then
            SHELL_PATH="/usr/bin/bash"
        else
            echo "csh: bash is not installed" >&2
            exit 1
        fi
        ;;
    *)
        echo "csh: unsupported shell '$TARGET' (use 'zsh' or 'bash')" >&2
        exit 1
        ;;
esac

TARGET_USER="${USER:-$(id -un)}"

if [ "$TEMP_ONLY" -eq 0 ]; then
    if [ "$(id -u)" -eq 0 ]; then
        if command -v usermod >/dev/null 2>&1; then
            usermod -s "$SHELL_PATH" "$TARGET_USER" 2>/dev/null || true
        else
            awk -F: -v OFS=: -v u="$TARGET_USER" -v s="$SHELL_PATH" '$1==u {$7=s} {print}' /etc/passwd > /etc/passwd.tmp && mv /etc/passwd.tmp /etc/passwd
        fi
        if [ "$TARGET_USER" = "root" ] && [ -f /etc/default/useradd ]; then
            sed -i "s|^SHELL=.*|SHELL=${SHELL_PATH}|" /etc/default/useradd 2>/dev/null || true
        fi
    elif command -v chsh >/dev/null 2>&1; then
        chsh -s "$SHELL_PATH" "$TARGET_USER"
    fi
fi

if [ "$SET_ONLY" -eq 1 ]; then
    printf '%s\n' "$SHELL_PATH"
    exit 0
fi

export SHELL="$SHELL_PATH"
exec "$SHELL_PATH" -l
CSH_EOF
    chmod 0755 /usr/bin/csh
    if [ ! -e /bin/csh ]; then
        ln -sfv /usr/bin/csh /bin/csh
    fi

    cat > /etc/profile.d/bhl-csh.sh << 'PROF_EOF'
csh() {
    case "${1:-}" in
        zsh|bash|/bin/zsh|/usr/bin/zsh|/bin/bash|/usr/bin/bash)
            local next_sh
            next_sh="$(/usr/bin/csh --set-only "$@")" || return $?
            export SHELL="$next_sh"
            exec "$next_sh" -l
            ;;
        -t|--temp)
            if [ -n "${2:-}" ]; then
                local next_sh
                next_sh="$(/usr/bin/csh --set-only -t "$2")" || return $?
                export SHELL="$next_sh"
                exec "$next_sh" -l
            else
                /usr/bin/csh "$@"
            fi
            ;;
        *)
            /usr/bin/csh "$@"
            ;;
    esac
}
PROF_EOF
    chmod 0644 /etc/profile.d/bhl-csh.sh

    if [ -f /etc/bashrc ] && ! grep -q "bhl-csh.sh" /etc/bashrc 2>/dev/null; then
        printf '\n[ -r /etc/profile.d/bhl-csh.sh ] && . /etc/profile.d/bhl-csh.sh\n' >> /etc/bashrc
    fi
    if [ -f /etc/bash.bashrc ] && ! grep -q "bhl-csh.sh" /etc/bash.bashrc 2>/dev/null; then
        printf '\n[ -r /etc/profile.d/bhl-csh.sh ] && . /etc/profile.d/bhl-csh.sh\n' >> /etc/bash.bashrc
    fi

    cat > /etc/zsh/zprofile << 'ZPROF_EOF'
export PATH=/usr/bin:/bin
if [ "$EUID" -eq 0 ]; then
    export PATH="/usr/sbin:/sbin:$PATH"
fi

export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/share}"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-$USER}"

for script in /etc/profile.d/*.sh; do
    if [ -r "$script" ]; then
        . "$script"
    fi
done
unset script
ZPROF_EOF

    cat > /etc/zsh/zshrc << 'ZSHRC_EOF'
HISTFILE="${HOME}/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY INC_APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE
setopt AUTO_CD INTERACTIVE_COMMENTS PROMPT_SUBST

autoload -Uz compinit colors
compinit -d "${HOME}/.zcompdump" 2>/dev/null
colors

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

bindkey -e
bindkey '^[[3~' delete-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search

alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

if [ "$EUID" -eq 0 ]; then
    PROMPT='%F{red}%B[%n@%m %1~]#%b%f '
else
    PROMPT='%F{cyan}%B[%n@%m %1~]$%b%f '
fi

[ -r /etc/profile.d/bhl-csh.sh ] && . /etc/profile.d/bhl-csh.sh
ZSHRC_EOF

    if [ ! -f /root/.zshrc ]; then
        cp /etc/zsh/zshrc /root/.zshrc
    fi

    /usr/bin/csh --set-only zsh >/dev/null 2>&1 || true

    if ! type -p zsh csh &>/dev/null; then
        echo "Error: zsh or csh binary not found in PATH!"
        exit 1
    fi

    cd "$INITIAL_DIR" || exit 1
else
    echo "No archive found."
    echo "Try to re-run this script"
    exit 1
fi

rm -rf "/sources/extra/zsh-${ZSH_VERSION}/"
rm -f "/sources/extra/zsh-${ZSH_VERSION}.tar.xz"

echo "Successfully installed zsh-${ZSH_VERSION} and csh shell switcher (default: zsh)"
