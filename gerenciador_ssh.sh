#!/usr/bin/env bash
# gerenciador_ssh_profissional.sh
# Versão: 1.0
# Descrição: Gerenciador SSH completo - gestão de usuários, segurança, monitoramento,
#           instalação automática e relatórios. Feito para uso em servidores Debian/Ubuntu.

# --- Configurações ---
LOG_FILE="/var/log/gerenciador_ssh.log"
REPO_URL="https://github.com/usuario/gerenciador_ssh.git" # Troque pelo seu repo
SCRIPT_NAME="gerenciador_ssh_profissional.sh"

set -euo pipefail
IFS=$'\n\t'

# --- Utils ---
log() {
  local msg="$(date +'%Y-%m-%d %H:%M:%S') - $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root." >&2
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ensure_dependency() {
  local dep="$1"
  if ! command_exists "$dep"; then
    log "Instalando dependência: $dep"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$dep" >/dev/null
  fi
}

safe_read() {
  # leitura segura sem expor variáveis em pipelines
  local __resultvar=$1
  shift
  read -r "$__resultvar" "$@"
}

# --- Inicialização ---
init() {
  require_root
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
  log "Inicializando $SCRIPT_NAME"
  # instalar whiptail se não existir
  ensure_dependency whiptail
}

# --- Funções de Usuário SSH ---
ssh_user_create() {
  local username="$1"
  local pubkey_file="$2" # opcional

  if id "$username" >/dev/null 2>&1; then
    log "Usuário $username já existe"
    return 1
  fi

  useradd -m -s /bin/bash "$username"
  passwd -l "$username" >/dev/null 2>&1 || true
  usermod -aG ssh "$username" || true

  # configurar .ssh
  local sshdir="/home/$username/.ssh"
  mkdir -p "$sshdir"
  chmod 700 "$sshdir"
  touch "$sshdir/authorized_keys"
  chmod 600 "$sshdir/authorized_keys"
  chown -R "$username:$username" "$sshdir"

  if [[ -n "$pubkey_file" && -f "$pubkey_file" ]]; then
    cat "$pubkey_file" >> "$sshdir/authorized_keys"
    chown "$username:$username" "$sshdir/authorized_keys"
  fi

  log "Criado usuário SSH: $username"
}

ssh_user_delete() {
  local username="$1"
  if ! id "$username" >/dev/null 2>&1; then
    log "Usuário $username não existe"
    return 1
  fi
  pkill -u "$username" || true
  userdel -r "$username"
  log "Deletado usuário: $username"
}

ssh_user_lock() {
  local username="$1"
  usermod -L "$username"
  log "Bloqueado usuário: $username"
}

ssh_user_unlock() {
  local username="$1"
  usermod -U "$username"
  log "Desbloqueado usuário: $username"
}

ssh_user_list() {
  echo "Usuários com /home:" 
  awk -F: '/\/home/ {print $1}' /etc/passwd
}

ssh_active_sessions() {
  echo "Sessões ativas (who):"
  who
  echo
  echo "sshd conexões (ss -tnp | grep sshd):"
  ss -tnp | grep sshd || true
}

ssh_user_report() {
  local username="$1"
  if ! id "$username" >/dev/null 2>&1; then
    echo "Usuário não encontrado"
    return 1
  fi
  echo "Relatório para $username"
  last -a | grep "^$username" || true
  ps -u "$username" -o pid,cmd || true
  du -sh /home/$username 2>/dev/null || true
}

# --- Monitoramento do Sistema ---
system_status() {
  echo "Uptime: $(uptime -p)"
  echo "Load: $(cat /proc/loadavg)"
  echo "Memória:"
  free -h
  echo
  echo "Disco:"
  df -h
  echo
  echo "Top processos por CPU:"
  ps aux --sort=-%cpu | head -n 10
}

# --- Segurança: instalar e configurar ---
setup_basic_security() {
  log "Configurando segurança básica (openssh-server, fail2ban, ufw)"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server fail2ban ufw >/dev/null

  # exemplo de configuração mínima do UFW
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw --force enable

  # Fail2ban configuração básica
  if [[ -f /etc/fail2ban/jail.local ]]; then
    log "Fail2ban já tem jail.local"
  else
    cat >/etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
maxretry = 5
bantime = 3600
EOF
  fi
  systemctl restart fail2ban || true
  systemctl enable fail2ban || true
  log "Segurança básica configurada"
}

# --- Instalador / Atualizador (para usar no GitHub) ---
install_from_repo() {
  local target_dir="/opt/gerenciador_ssh"
  mkdir -p "$target_dir"
  if command_exists git; then
    if [[ -d "$target_dir/.git" ]]; then
      git -C "$target_dir" pull
    else
      git clone "$REPO_URL" "$target_dir"
    fi
    ln -sf "$target_dir/$SCRIPT_NAME" /usr/local/bin/gerenciador_ssh
    chmod +x "$target_dir/$SCRIPT_NAME"
    log "Instalado/atualizado a partir do repositório"
  else
    log "git não encontrado, instalando git..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y git >/dev/null
    install_from_repo
  fi
}

# --- Relatórios ---
generate_report() {
  local outfile="/tmp/gerenciador_ssh_report_$(date +%Y%m%d_%H%M%S).txt"
  {
    echo "Relatório gerado: $(date)"
    echo
    echo "=== UPTIME & LOAD ==="
    uptime
    echo
    echo "=== MEMÓRIA ==="
    free -h
    echo
    echo "=== DISCO ==="
    df -h
    echo
    echo "=== SESSÕES ATIVAS ==="
    who
    echo
    echo "=== LOGINS RECENTES (last -n 50) ==="
    last -n 50
  } >"$outfile"
  log "Relatório gerado: $outfile"
  echo "$outfile"
}

# --- Interface com whiptail ---
main_menu() {
  while true; do
    CHOICE=$(whiptail --title "Gerenciador SSH - Profissional" --menu "Escolha uma opção" 20 78 12 \
      "1" "Usuários SSH: Criar/Listar/Bloquear/Excluir" \
      "2" "Sessões ativas / Relatórios" \
      "3" "Monitoramento do Sistema" \
      "4" "Configurar segurança básica (openssh/fail2ban/ufw)" \
      "5" "Instalar/Atualizar via GitHub" \
      "6" "Gerar relatório" \
      "7" "Sair" 3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then
      log "Usuário saiu do menu"
      break
    fi

    case "$CHOICE" in
      "1")
        user_management_menu
        ;;
      "2")
        ssh_active_sessions | less
        ;;
      "3")
        system_status | less
        ;;
      "4")
        setup_basic_security
        whiptail --msgbox "Segurança básica configurada." 8 40
        ;;
      "5")
        install_from_repo
        whiptail --msgbox "Instalado/atualizado a partir do repositório." 8 40
        ;;
      "6")
        local report
        report=$(generate_report)
        whiptail --msgbox "Relatório salvo em: $report" 8 60
        ;;
      "7")
        log "Saindo"
        break
        ;;
    esac
  done
}

user_management_menu() {
  while true; do
    UMENU=$(whiptail --title "Usuários SSH" --menu "Escolha" 20 70 10 \
      "1" "Criar usuário" \
      "2" "Listar usuários" \
      "3" "Bloquear usuário" \
      "4" "Desbloquear usuário" \
      "5" "Excluir usuário" \
      "6" "Gerar relatório do usuário" \
      "7" "Voltar" 3>&1 1>&2 2>&3)

    rc=$?
    if [ $rc -ne 0 ]; then
      break
    fi

    case "$UMENU" in
      "1")
        username=$(whiptail --inputbox "Nome do usuário:" 8 40 3>&1 1>&2 2>&3)
        pubkey=$(whiptail --inputbox "Caminho para chave pública (opcional):" 8 60 3>&1 1>&2 2>&3)
        ssh_user_create "$username" "$pubkey"
        whiptail --msgbox "Usuário $username criado (ou tente ver logs)." 8 60
        ;;
      "2")
        users=$(ssh_user_list)
        whiptail --msgbox "Usuarios:\n$users" 20 70
        ;;
      "3")
        username=$(whiptail --inputbox "Nome do usuário para bloquear:" 8 40 3>&1 1>&2 2>&3)
        ssh_user_lock "$username"
        whiptail --msgbox "Usuário $username bloqueado." 8 40
        ;;
      "4")
        username=$(whiptail --inputbox "Nome do usuário para desbloquear:" 8 40 3>&1 1>&2 2>&3)
        ssh_user_unlock "$username"
        whiptail --msgbox "Usuário $username desbloqueado." 8 40
        ;;
      "5")
        username=$(whiptail --inputbox "Nome do usuário para excluir:" 8 40 3>&1 1>&2 2>&3)
        if whiptail --yesno "Tem certeza que deseja excluir $username?" 8 60; then
          ssh_user_delete "$username"
          whiptail --msgbox "Usuário $username excluído." 8 40
        fi
        ;;
      "6")
        username=$(whiptail --inputbox "Nome do usuário para relatório:" 8 40 3>&1 1>&2 2>&3)
        ssh_user_report "$username" | less
        ;;
      "7")
        break
        ;;
    esac
  done
}

# --- CLI simples (para uso sem whiptail) ---
usage() {
  cat <<EOF
Gerenciador SSH - Uso:
  $0 --install            # Instala dependências e configura segurança básica
  $0 --create USER [PUBKEY]  # Cria usuário SSH
  $0 --delete USER       # Deleta usuário
  $0 --lock USER         # Bloqueia usuário
  $0 --unlock USER       # Desbloqueia usuário
  $0 --list              # Lista usuários com /home
  $0 --status            # Status do sistema
  $0 --report            # Gera relatório completo
  $0 --menu              # Abre interface whiptail
  $0 --install-repo      # Instala/atualiza a partir do repositório
EOF
}

# --- Argumentos CLI ---
main() {
  init
  if [[ $# -eq 0 ]]; then
    main_menu
    exit 0
  fi

  case "$1" in
    --install)
      setup_basic_security
      ;;
    --create)
      ssh_user_create "$2" "${3-}"
      ;;
    --delete)
      ssh_user_delete "$2"
      ;;
    --lock)
      ssh_user_lock "$2"
      ;;
    --unlock)
      ssh_user_unlock "$2"
      ;;
    --list)
      ssh_user_list
      ;;
    --status)
      system_status
      ;;
    --report)
      generate_report
      ;;
    --menu)
      main_menu
      ;;
    --install-repo)
      install_from_repo
      ;;
    --help|-h)
      usage
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
