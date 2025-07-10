#!/bin/bash
echo -e "\n===== Lendo arquivo de configuração =====\n"
source ./serverconfig.cfg
LOGFILE="/var/log/server_setup.log" # Arquivo de log

echo -e "\n===== CONFIGURANDO IP FIXO (via NetworkManager) =====\n"

# Detecta interface padrão
echo "[INFO] Detectando interface de rede padrão..."
IFACE=$(ip -o -4 route show to default | awk '{print $5}')
echo "[INFO] Interface detectada: $IFACE"

# Verifica configuração atual
echo "[INFO] Verificando configuração atual de IP, Gateway e DNS..."
IP_ATUAL=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\dcle+){3}')
GATEWAY_ATUAL=$(ip route | grep default | awk '{print $3}')
DNS_ATUAL=$(nmcli dev show "$IFACE" | grep DNS | awk '{print $2}' | paste -sd " ")

if [[ "$IP_ATUAL/24" == "$FIXED_IP" && "$GATEWAY_ATUAL" == "$GATEWAY" && "$DNS_ATUAL" == "$DNS" ]]; then
  echo "[INFO] IP, Gateway e DNS já estão corretamente configurados."
else
  echo "[INFO] Aplicando nova configuração IP com nmcli..."
  # Remove conexão anterior com mesmo nome se existir
  nmcli con delete "${IFACE}-static" &>/dev/null
  # Cria nova conexão estática
  nmcli con add con-name "${IFACE}-static" ifname "$IFACE" type ethernet ipv4.addresses "$FIXED_IP" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS" ipv4.method manual >> "$LOGFILE" 2>&1
  sleep 5
  nmcli con up "${IFACE}-static" >> "$LOGFILE" 2>&1
  ip route add default via "$GATEWAY" dev "$IFACE" 2>/dev/null
fi

# Verifica conectividade do IP fixo
echo -e "\n===== VERIFICANDO CONECTIVIDADE =====\n"
sleep 5
echo "[INFO] Testando ping para 8.8.8.8..."
if ping -c 3 8.8.8.8 > /dev/null 2>&1; then
  echo "[OK] Conectividade confirmada."
else
  echo "[ERRO] Sem acesso à internet. Abortando..."
  exit 1
fi

sleep 3

echo -e "\n===== INICIANDO CONFIGURAÇÃO DO SERVIDOR =====\n"

# Instalar/verificar apt-get
echo -e "\n===== VERIFICANDO E INSTALANDO APT-GET =====\n"
if ! command -v apt-get &>/dev/null; then
    echo "[INFO] apt-get não encontrado. Instalando..."
    wget -q -v --show-progress -O /tmp/apt.deb "$APT_URL"
    dpkg -i /tmp/apt.deb
elif ! apt-get -v | grep -q "$APT_EXPECTED_VERSION"; then
    echo "[INFO] apt-get desatualizado. Atualizando..."
    wget -q -v --show-progress -O /tmp/apt.deb "$APT_URL"
    dpkg -i /tmp/apt.deb
else
    echo "[INFO] apt-get já está na versão $APT_EXPECTED_VERSION. Executando apt-get update..."
    apt-get update
fi

# PATH fix
echo -e "\n===== CONFIGURANDO PATH =====\n"
export PATH="$PATH:/usr/sbin"

# Instalar passwd se necessário
if ! dpkg -s passwd &>/dev/null; then
    echo "[INFO] Instalando pacote passwd..."
    apt-get install -y -v passwd
fi

# Limpar CD-ROM
echo -e "\n===== REMOVENDO CD-ROM DA LISTA DE FONTES =====\n"
sed -i '/cdrom:/s/^/#/' /etc/network/interfaces

# Adicionar repositórios Debian
echo -e "\n===== ADICIONANDO REPOSITÓRIOS DEBIAAN =====\n"
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free
deb http://security.debian.org/debian-security bookworm-security main contrib non-free
EOF

apt-get update

# Criar grupo sudo se necessário
echo -e "\n===== VERIFICANDO E CRIANDO GRUPO SUDO =====\n"
if ! getent group sudo >/dev/null; then
    groupadd sudo
fi

# Criar usuário se não existir
if ! id "$USER_NAME" &>/dev/null; then
echo -e "\n===== CRIANDO USUÁRIO =====\n"
    adduser --disabled-password --gecos "" "$USER_NAME"
fi

# Adicionar usuário ao grupo sudo
if ! groups "$USER_NAME" | grep -qw "sudo"; then
echo -e "\n===== ADICIONANDO USUÁRIO AO GRUPO SUDO =====\n"
    usermod -aG sudo "$USER_NAME"
fi

# Instalar/verificar JDK
echo -e "\n===== VERIFICANDO E INSTALANDO JDK =====\n"
JAVA_PATH="/opt/java/java-21/bin/java"
JAVA_VERSION_INSTALLED=$($JAVA_PATH -version 2>&1 | grep 'version' | awk '{print $2}' | tr -d '"') || true

echo "[INFO] Adicionando repositório backports para OpenJDK 21..."
echo "deb http://deb.debian.org/debian bookworm-backports main" | tee -a /etc/apt/sources.list.d/backports.list
apt-get update -y -v

echo "[INFO] Instalando OpenJDK 21 via apt-get..."
apt-get install -y -v -t bookworm-backports openjdk-21-jdk

echo "[INFO] Verificando versão do Java..."
java -version | tee -a "$LOGFILE"

# Instalar htop se disponível
if apt-cache show htop &>/dev/null && ! dpkg -s htop &>/dev/null; then
echo -e "\n===== INSTALANDO HTOP =====\n"
    apt-get install -y -v htop
fi

echo -e "\n===== CONFIGURAÇÃO FINALIZADA COM SUCESSO =====\n"
echo "[INFO] Reiniciando o sistema em 5 segundos..."
sleep 5
echo "[INFO] Reiniciando agora..."
sleep 5
reboot
