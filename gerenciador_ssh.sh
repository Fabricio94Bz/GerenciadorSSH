#!/bin/bash
# ===========================================
#   GERENCIADOR SSH AVANÇADO COM RELATÓRIOS E API
#   Ubuntu 20.04 / 22.04 / 24.04
# ===========================================

LIMIT_FILE="/etc/ssh/ssh_limits.conf"
LOG_FILE="/var/log/ssh_manager.log"
touch "$LIMIT_FILE" "$LOG_FILE"

menu() {
  clear
  echo "==========================================="
  echo "      GERENCIADOR DE USUÁRIOS SSH"
  echo "==========================================="
  echo "1) Criar novo usuário"
  echo "2) Remover usuário"
  echo "3) Listar usuários ativos"
  echo "4) Criar usuário temporário"
  echo "5) Definir limite de conexões"
  echo "6) Ver logins ativos"
  echo "7) Gerar relatório diário"
  echo "8) Iniciar API HTTP local"
  echo "9) Sair"
  echo "==========================================="
  read -p "Escolha uma opção: " opcao

  case $opcao in
    1) criar_usuario ;;
    2) remover_usuario ;;
    3) listar_usuarios ;;
    4) criar_usuario_temporario ;;
    5) limitar_conexoes ;;
    6) ver_logins ;;
    7) gerar_relatorio ;;
    8) iniciar_api ;;
    9) exit 0 ;;
    *) echo "Opção inválida!"; sleep 1; menu ;;
  esac
}

criar_usuario() {
  read -p "Usuário: " user
  read -s -p "Senha: " pass
  echo
  useradd -m -s /bin/bash "$user"
  echo "$user:$pass" | chpasswd
  echo "$(date '+%F %T') - Criado usuário $user" >> "$LOG_FILE"
  echo "Usuário $user criado com sucesso!"
  sleep 2
  menu
}

remover_usuario() {
  read -p "Usuário a remover: " user
  userdel -r "$user" 2>/dev/null
  sed -i "/^$user:/d" "$LIMIT_FILE"
  echo "$(date '+%F %T') - Removido usuário $user" >> "$LOG_FILE"
  echo "Usuário $user removido."
  sleep 2
  menu
}

listar_usuarios() {
  echo "Usuários SSH ativos:"
  awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd
  echo
  read -p "Pressione Enter para voltar..."
  menu
}

criar_usuario_temporario() {
  read -p "Usuário: " user
  read -s -p "Senha: " pass
  echo
  read -p "Duração da conta (em dias): " dias
  useradd -m -s /bin/bash "$user"
  echo "$user:$pass" | chpasswd
  chage -E $(date -d "+$dias days" +"%Y-%m-%d") "$user"
  echo "$(date '+%F %T') - Criado usuário temporário $user ($dias dias)" >> "$LOG_FILE"
  echo "Usuário $user criado e expira em $dias dias!"
  sleep 2
  menu
}

limitar_conexoes() {
  read -p "Usuário: " user
  read -p "Limite de conexões simultâneas: " limite
  if id "$user" &>/dev/null; then
    sed -i "/^$user:/d" "$LIMIT_FILE"
    echo "$user:$limite" >> "$LIMIT_FILE"
    echo "$(date '+%F %T') - Limite de $limite conexões definido para $user" >> "$LOG_FILE"
    echo "Limite definido: $user pode ter até $limite conexões."
  else
    echo "Usuário $user não encontrado."
  fi
  sleep 2
  menu
}

ver_logins() {
  echo "Logins SSH ativos:"
  echo "-------------------------------------------"
  ss -o state established '( dport = :ssh )' | awk '/ESTAB/ {print $6}' | cut -d':' -f1 | sort | uniq -c
  echo "-------------------------------------------"
  echo
  read -p "Pressione Enter para voltar..."
  menu
}

gerar_relatorio() {
  echo "Gerando relatório diário..."
  echo "==========================================="
  echo "Relatório SSH - $(date)" > /root/relatorio_ssh.txt
  echo "" >> /root/relatorio_ssh.txt
  echo "Usuários ativos:" >> /root/relatorio_ssh.txt
  awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd >> /root/relatorio_ssh.txt
  echo "" >> /root/relatorio_ssh.txt
  echo "Logins ativos no momento:" >> /root/relatorio_ssh.txt
  ss -o state established '( dport = :ssh )' | awk '/ESTAB/ {print $6}' | cut -d':' -f1 | sort | uniq -c >> /root/relatorio_ssh.txt
  echo "" >> /root/relatorio_ssh.txt
  echo "Últimas ações registradas:" >> /root/relatorio_ssh.txt
  tail -n 10 "$LOG_FILE" >> /root/relatorio_ssh.txt
  echo "Relatório salvo em /root/relatorio_ssh.txt"
  sleep 2
  menu
}

iniciar_api() {
  echo "Iniciando API HTTP local na porta 8080..."
  nohup python3 /usr/local/bin/api_ssh.py > /dev/null 2>&1 &
  echo "API rodando em http://localhost:8080"
  sleep 2
  menu
}

# Criação do script auxiliar para limite de conexões
cat << 'EOF' > /usr/local/bin/ssh_limit_check.sh
#!/bin/bash
LIMIT_FILE="/etc/ssh/ssh_limits.conf"
user="$PAM_USER"

if grep -q "^$user:" "$LIMIT_FILE"; then
  limit=$(grep "^$user:" "$LIMIT_FILE" | cut -d':' -f2)
  current=$(pgrep -u "$user" | wc -l)
  if [ "$current" -gt "$limit" ]; then
    echo "Usuário $user atingiu o limite de conexões ($limit)." >&2
    exit 1
  fi
fi
EOF

chmod +x /usr/local/bin/ssh_limit_check.sh

# Configurar PAM (se ainda não configurado)
if ! grep -q "ssh_limit_check.sh" /etc/pam.d/sshd; then
  echo 'session required pam_exec.so /usr/local/bin/ssh_limit_check.sh' | tee -a /etc/pam.d/sshd > /dev/null
fi

menu
