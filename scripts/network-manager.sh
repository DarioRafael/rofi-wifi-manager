#!/bin/bash

# Rofi Network Manager - Script principal
CONFIG_DIR="$HOME/.config/rofi/data"
SCRIPTS_DIR="$HOME/.config/rofi/scripts"
PASSWORDS_FILE="$CONFIG_DIR/wifi_passwords"
LOG_FILE="$CONFIG_DIR/network.log"

# Crear directorios si no existen
mkdir -p "$CONFIG_DIR"
touch "$PASSWORDS_FILE"
touch "$LOG_FILE"
chmod 600 "$PASSWORDS_FILE"

# Función para logging
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_FILE"
}

# Función para detectar el administrador de red
detect_network_manager() {
  if command -v nmcli &>/dev/null; then
    echo "networkmanager"
  elif command -v iwctl &>/dev/null; then
    echo "iwd"
  else
    echo "none"
  fi
}

# Función para obtener estado de conexión
get_connection_status() {
  local nm_type=$(detect_network_manager)

  case $nm_type in
  "networkmanager")
    nmcli device status | grep "wifi" | grep "connected" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}'
    ;;
  "iwd")
    iwctl station wlan0 show | grep "Connected network" | awk '{print $3}'
    ;;
  esac
}

# Función principal del menú
main_menu() {
  local connected_network=$(get_connection_status)
  local status_text=""
  local wifi_option=""

  if [[ -n "$connected_network" ]]; then
    status_text="📶 Conectado a: $(echo $connected_network | xargs)"
    wifi_option="🔌 Desconectar WiFi"
  else
    status_text="📶 No conectado"
    wifi_option="📶 Conectar a WiFi"
  fi

  local options="🔍 Escanear y conectar WiFi
$wifi_option
📡 Crear hotspot
🛑 Detener hotspot
🔧 Configuración avanzada
📊 Ver estado de red
❌ Salir"

  local choice=$(echo -e "$options" | rofi -dmenu -p "$status_text" -i -theme ~/.config/rofi/config/network.rasi)

  case "$choice" in
  "🔍 Escanear y conectar WiFi")
    bash "$SCRIPTS_DIR/wifi-connect.sh"
    ;;
  "🔌 Desconectar WiFi")
    disconnect_wifi
    ;;
  "📶 Conectar a WiFi")
    bash "$SCRIPTS_DIR/wifi-connect.sh"
    ;;
  "📡 Crear hotspot")
    bash "$SCRIPTS_DIR/hotspot-manager.sh" create
    ;;
  "🛑 Detener hotspot")
    bash "$SCRIPTS_DIR/hotspot-manager.sh" stop
    ;;
  "🔧 Configuración avanzada")
    advanced_menu
    ;;
  "📊 Ver estado de red")
    show_network_status
    ;;
  "❌ Salir")
    exit 0
    ;;
  *)
    if [[ -n "$choice" ]]; then
      main_menu
    fi
    ;;
  esac
}

# Función para desconectar WiFi
disconnect_wifi() {
  local nm_type=$(detect_network_manager)

  case $nm_type in
  "networkmanager")
    nmcli device disconnect wlan0
    ;;
  "iwd")
    iwctl station wlan0 disconnect
    ;;
  esac

  notify-send "WiFi" "Desconectado" -i network-wireless-disconnected
  log_message "WiFi desconectado"
  # Volver al menú principal para actualizar el estado
  main_menu
}

# Función para configuración avanzada
advanced_menu() {
  local options="🌐 Configurar DNS
🔒 Gestionar conexiones guardadas
📡 Configurar proxy
🔄 Reiniciar servicios de red
⬅️ Volver al menú principal"

  local choice=$(echo -e "$options" | rofi -dmenu -p "Configuración avanzada" -i)

  case "$choice" in
  "🌐 Configurar DNS")
    configure_dns
    ;;
  "🔒 Gestionar conexiones guardadas")
    manage_saved_connections
    ;;
  "📡 Configurar proxy")
    configure_proxy
    ;;
  "🔄 Reiniciar servicios de red")
    restart_network_services
    ;;
  "⬅️ Volver al menú principal")
    main_menu
    ;;
  esac
}

# Función para mostrar estado de red
show_network_status() {
  local nm_type=$(detect_network_manager)
  local status=""

  case $nm_type in
  "networkmanager")
    status=$(nmcli general status && echo -e "\n--- Dispositivos ---" && nmcli device status)
    ;;
  "iwd")
    status=$(iwctl station wlan0 show)
    ;;
  esac

  echo -e "$status" | rofi -dmenu -p "Estado de red" -i -no-custom
}

# Funciones adicionales de configuración avanzada
configure_dns() {
  local dns=$(rofi -dmenu -p "Servidor DNS (ej: 8.8.8.8,1.1.1.1):")
  if [[ -n "$dns" ]]; then
    nmcli connection modify "$(nmcli -t -f NAME connection show --active | head -1)" ipv4.dns "$dns"
    nmcli connection up "$(nmcli -t -f NAME connection show --active | head -1)"
    notify-send "DNS" "DNS configurado: $dns" -i network-wired
    log_message "DNS configurado: $dns"
  fi
}

manage_saved_connections() {
  local connections=$(nmcli -t -f NAME connection show | rofi -dmenu -p "Seleccionar conexión para eliminar:")
  if [[ -n "$connections" ]]; then
    local confirm=$(echo -e "Sí\nNo" | rofi -dmenu -p "¿Eliminar conexión '$connections'?")
    if [[ "$confirm" == "Sí" ]]; then
      nmcli connection delete "$connections"
      notify-send "Conexión" "Conexión '$connections' eliminada" -i dialog-info
      log_message "Conexión eliminada: $connections"
    fi
  fi
}

configure_proxy() {
  local proxy=$(rofi -dmenu -p "Proxy HTTP (ej: http://proxy:8080):")
  if [[ -n "$proxy" ]]; then
    export http_proxy="$proxy"
    export https_proxy="$proxy"
    notify-send "Proxy" "Proxy configurado: $proxy" -i network-wired
    log_message "Proxy configurado: $proxy"
  fi
}

restart_network_services() {
  local nm_type=$(detect_network_manager)

  case $nm_type in
  "networkmanager")
    sudo systemctl restart NetworkManager
    ;;
  "iwd")
    sudo systemctl restart iwd
    ;;
  esac

  notify-send "Red" "Servicios de red reiniciados" -i network-wired
  log_message "Servicios de red reiniciados"
}

# Ejecutar menú principal si se ejecuta directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_menu
fi
