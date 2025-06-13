#!/bin/bash

CONFIG_DIR="$HOME/.config/rofi/data"
LOG_FILE="$CONFIG_DIR/network.log"

# Función para logging
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_FILE"
}

# Función para ping a un host
ping_host() {
  local host=$(rofi -dmenu -p "🌐 Host para hacer ping (ej: google.com):")
  [[ -z "$host" ]] && exit 0

  local result=$(ping -c 4 "$host" 2>&1)
  echo -e "Resultado del ping a $host:\n\n$result" | rofi -dmenu -p "Ping Result" -no-custom
  log_message "Ping realizado a: $host"
}

# Función para mostrar información de IP
show_ip_info() {
  local ip_info=""

  # IP pública
  local public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "No disponible")

  # IPs locales
  local local_ips=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1)

  # Gateway
  local gateway=$(ip route | grep default | awk '{print $3}' | head -1)

  # DNS
  local dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')

  ip_info="🌐 Información de Red:

📍 IP Pública: $public_ip

🏠 IPs Locales:
$local_ips

🚪 Gateway: ${gateway:-No disponible}

🔍 Servidores DNS: ${dns_servers:-No disponible}"

  echo -e "$ip_info" | rofi -dmenu -p "Información IP" -no-custom
}

# Función para escanear puertos
port_scan() {
  local host=$(rofi -dmenu -p "🖥️ Host para escanear (ej: 192.168.1.1):")
  [[ -z "$host" ]] && exit 0

  local ports=$(rofi -dmenu -p "🔌 Puertos a escanear (ej: 22,80,443 o 1-100):")
  [[ -z "$ports" ]] && exit 0

  # Usar nmap si está disponible, sino nc
  if command -v nmap &>/dev/null; then
    local result=$(nmap -p "$ports" "$host" 2>&1)
  else
    local result="Escaneando puertos básicos con netcat...\n"
    for port in $(echo "$ports" | tr ',' ' '); do
      if timeout 2 nc -z "$host" "$port" 2>/dev/null; then
        result+="\nPuerto $port: ABIERTO"
      else
        result+="\nPuerto $port: CERRADO"
      fi
    done
  fi

  echo -e "Escaneo de puertos en $host:\n\n$result" | rofi -dmenu -p "Port Scan" -no-custom
  log_message "Escaneo de puertos realizado: $host:$ports"
}

# Función para mostrar tráfico de red
show_network_traffic() {
  local interface=$(ip link show | grep -E "^[0-9]" | grep -v lo | awk -F': ' '{print $2}' | rofi -dmenu -p "Seleccionar interfaz:")
  [[ -z "$interface" ]] && exit 0

  local traffic_info=$(cat /proc/net/dev | grep "$interface" | awk -v iface="$interface" '
    {
        rx_bytes = $2
        tx_bytes = $10
        printf "📊 Tráfico de red - %s:\n\n", iface
        printf "📥 Recibido: %.2f MB\n", rx_bytes/1024/1024
        printf "📤 Enviado: %.2f MB\n", tx_bytes/1024/1024
        printf "📋 Total: %.2f MB", (rx_bytes+tx_bytes)/1024/1024
    }')

  echo -e "$traffic_info" | rofi -dmenu -p "Tráfico de Red" -no-custom
}

# Función para speed test básico
speed_test() {
  local test_type=$(echo -e "Descarga\nSubida\nAmbos" | rofi -dmenu -p "Tipo de test de velocidad:")
  [[ -z "$test_type" ]] && exit 0

  echo "🚀 Realizando test de velocidad..." | rofi -dmenu -p "Speed Test" -no-custom &
  ROFI_PID=$!

  local result=""

  case "$test_type" in
  "Descarga")
    local download_speed=$(curl -s -w "%{speed_download}" -o /dev/null http://speedtest.wdc01.softlayer.com/downloads/test10.zip)
    result="📥 Velocidad de descarga: $(echo "scale=2; $download_speed / 1024 / 1024" | bc) MB/s"
    ;;
  "Subida")
    # Test de subida básico
    local upload_speed=$(dd if=/dev/zero bs=1M count=1 2>/dev/null | curl -s -w "%{speed_upload}" -X POST --data-binary @- http://httpbin.org/post -o /dev/null)
    result="📤 Velocidad de subida: $(echo "scale=2; $upload_speed / 1024 / 1024" | bc) MB/s"
    ;;
  "Ambos")
    local download_speed=$(curl -s -w "%{speed_download}" -o /dev/null http://speedtest.wdc01.softlayer.com/downloads/test10.zip)
    local upload_speed=$(dd if=/dev/zero bs=1M count=1 2>/dev/null | curl -s -w "%{speed_upload}" -X POST --data-binary @- http://httpbin.org/post -o /dev/null)
    result="📊 Test de velocidad completo:
📥 Descarga: $(echo "scale=2; $download_speed / 1024 / 1024" | bc) MB/s
📤 Subida: $(echo "scale=2; $upload_speed / 1024 / 1024" | bc) MB/s"
    ;;
  esac

  kill $ROFI_PID 2>/dev/null
  echo -e "$result" | rofi -dmenu -p "Resultado Speed Test" -no-custom
  log_message "Speed test realizado: $test_type"
}

# Función para diagnóstico de red
network_diagnosis() {
  echo "🔍 Realizando diagnóstico de red..." | rofi -dmenu -p "Diagnóstico" -no-custom &
  ROFI_PID=$!

  local diagnosis=""

  # Verificar conectividad básica
  if ping -c 1 8.8.8.8 &>/dev/null; then
    diagnosis+="✅ Conectividad a internet: OK\n"
  else
    diagnosis+="❌ Conectividad a internet: FALLO\n"
  fi

  # Verificar DNS
  if nslookup google.com &>/dev/null; then
    diagnosis+="✅ Resolución DNS: OK\n"
  else
    diagnosis+="❌ Resolución DNS: FALLO\n"
  fi

  # Verificar gateway
  local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
  if [[ -n "$gateway" ]] && ping -c 1 "$gateway" &>/dev/null; then
    diagnosis+="✅ Gateway ($gateway): OK\n"
  else
    diagnosis+="❌ Gateway: FALLO\n"
  fi

  # Verificar interfaces
  local active_interfaces=$(ip link show up | grep -E "^[0-9]" | grep -v lo | wc -l)
  diagnosis+="ℹ️ Interfaces activas: $active_interfaces\n"

  kill $ROFI_PID 2>/dev/null
  echo -e "🔍 Diagnóstico de Red:\n\n$diagnosis" | rofi -dmenu -p "Diagnóstico Completo" -no-custom
  log_message "Diagnóstico de red realizado"
}

# Menú principal de utilidades
utils_menu() {
  local options="🌐 Ping a host
📋 Mostrar información IP
🔌 Escanear puertos
📊 Ver tráfico de red
🚀 Test de velocidad
🔍 Diagnóstico de red
⬅️ Volver"

  local choice=$(echo -e "$options" | rofi -dmenu -p "Utilidades de Red" -i)

  case "$choice" in
  "🌐 Ping a host")
    ping_host
    ;;
  "📋 Mostrar información IP")
    show_ip_info
    ;;
  "🔌 Escanear puertos")
    port_scan
    ;;
  "📊 Ver tráfico de red")
    show_network_traffic
    ;;
  "🚀 Test de velocidad")
    speed_test
    ;;
  "🔍 Diagnóstico de red")
    network_diagnosis
    ;;
  "⬅️ Volver")
    exit 0
    ;;
  esac
}

# Ejecutar menú si se llama directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  utils_menu
fi
