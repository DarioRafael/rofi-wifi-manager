#!/bin/bash

CONFIG_DIR="$HOME/.config/rofi/data"
LOG_FILE="$CONFIG_DIR/network.log"
HOTSPOT_CONFIG="$CONFIG_DIR/hotspot.conf"

# Función para logging
log_message() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_FILE"
}

# Función para detectar el administrador de red
detect_network_manager() {
  if command -v nmcli &>/dev/null; then
    echo "networkmanager"
  else
    echo "none"
  fi
}

# Función para crear hotspot
create_hotspot() {
  local ssid=$(rofi -dmenu -p "📡 Nombre del hotspot:" -theme ~/.config/rofi/config/network.rasi)
  [[ -z "$ssid" ]] && exit 0

  local password=$(rofi -dmenu -password -p "🔒 Contraseña del hotspot (min 8 caracteres):" -theme ~/.config/rofi/config/network.rasi)
  [[ -z "$password" ]] && exit 0

  if [[ ${#password} -lt 8 ]]; then
    notify-send "Error" "❌ La contraseña debe tener al menos 8 caracteres" -i dialog-error
    exit 1
  fi

  local nm_type=$(detect_network_manager)

  case $nm_type in
  "networkmanager")
    # Verificar si hay una conexión WiFi activa que desconectar
    local active_wifi=$(nmcli device status | grep "wifi" | grep "connected")
    if [[ -n "$active_wifi" ]]; then
      local confirm=$(echo -e "Sí\nNo" | rofi -dmenu -p "Se desconectará WiFi para crear hotspot. ¿Continuar?")
      if [[ "$confirm" != "Sí" ]]; then
        exit 0
      fi
      nmcli device disconnect wlan0
      sleep 2
    fi

    # Crear hotspot
    if nmcli device wifi hotspot con-name "hotspot-$ssid" ssid "$ssid" password "$password"; then
      # Guardar configuración
      echo "SSID=$ssid" >"$HOTSPOT_CONFIG"
      echo "PASSWORD=$password" >>"$HOTSPOT_CONFIG"
      echo "CREATED=$(date)" >>"$HOTSPOT_CONFIG"
      chmod 600 "$HOTSPOT_CONFIG"

      notify-send "Hotspot" "✅ Hotspot '$ssid' creado correctamente" -i network-wireless
      log_message "Hotspot creado: $ssid"

      # Mostrar información del hotspot
      show_hotspot_info "$ssid" "$password"
    else
      notify-send "Error" "❌ No se pudo crear el hotspot" -i dialog-error
      log_message "Error creando hotspot: $ssid"
    fi
    ;;
  *)
    notify-send "Error" "❌ Hotspot no soportado con el administrador de red actual" -i dialog-error
    ;;
  esac
}

# Función para mostrar información del hotspot
show_hotspot_info() {
  local ssid="$1"
  local password="$2"
  local device_ip=$(ip route | grep wlan0 | grep src | awk '{print $9}' | head -1)

  local info="📡 Hotspot activo:
Nombre: $ssid
Contraseña: $password
IP del dispositivo: ${device_ip:-N/A}

Los dispositivos conectados pueden acceder a internet a través de este hotspot."

  echo -e "$info" | rofi -dmenu -p "Información del Hotspot" -no-custom -theme ~/.config/rofi/config/network.rasi
}

# Función para detener hotspot
stop_hotspot() {
  local nm_type=$(detect_network_manager)

  case $nm_type in
  "networkmanager")
    # Encontrar y desactivar conexión de hotspot
    local hotspot_connections=$(nmcli connection show | grep "hotspot-" | awk '{print $1}')

    if [[ -n "$hotspot_connections" ]]; then
      local connection_count=$(echo "$hotspot_connections" | wc -l)
      local connection_to_stop=""

      if [[ $connection_count -eq 1 ]]; then
        connection_to_stop="$hotspot_connections"
      else
        # Si hay múltiples hotspots, permitir al usuario elegir
        connection_to_stop=$(echo "$hotspot_connections" | rofi -dmenu -p "Seleccionar hotspot para detener:")
      fi

      if [[ -n "$connection_to_stop" ]]; then
        nmcli connection down "$connection_to_stop"

        # Preguntar si eliminar la configuración guardada
        local delete_config=$(echo -e "Sí\nNo" | rofi -dmenu -p "¿Eliminar configuración del hotspot?")
        if [[ "$delete_config" == "Sí" ]]; then
          nmcli connection delete "$connection_to_stop"
          [[ -f "$HOTSPOT_CONFIG" ]] && rm "$HOTSPOT_CONFIG"
        fi

        notify-send "Hotspot" "✅ Hotspot desactivado" -i network-wireless-disconnected
        log_message "Hotspot desactivado: $connection_to_stop"
      else
        notify-send "Info" "ℹ️ Operación cancelada" -i dialog-info
      fi
    else
      notify-send "Info" "ℹ️ No hay hotspot activo" -i dialog-info
    fi
    ;;
  *)
    notify-send "Error" "❌ Hotspot no soportado con el administrador de red actual" -i dialog-error
    ;;
  esac
}

# Función para mostrar dispositivos conectados
show_connected_devices() {
  local connected_devices=$(arp -a | grep wlan0 2>/dev/null || echo "No se pudieron obtener los dispositivos conectados")

  if [[ "$connected_devices" != "No se pudieron obtener los dispositivos conectados" ]]; then
    local device_info="📱 Dispositivos conectados al hotspot:\n\n$connected_devices"
  else
    local device_info="📱 No se pudieron obtener los dispositivos conectados\n\nPuede deberse a permisos o que no haya dispositivos conectados."
  fi

  echo -e "$device_info" | rofi -dmenu -p "Dispositivos conectados" -no-custom
}

# Función para gestionar hotspot (menú)
hotspot_menu() {
  local options="📡 Crear nuevo hotspot
🛑 Detener hotspot
📱 Ver dispositivos conectados
ℹ️ Ver información del hotspot
⬅️ Volver"

  local choice=$(echo -e "$options" | rofi -dmenu -p "Gestión de Hotspot" -i -theme ~/.config/rofi/config/network.rasi)

  case "$choice" in
  "📡 Crear nuevo hotspot")
    create_hotspot
    ;;
  "🛑 Detener hotspot")
    stop_hotspot
    ;;
  "📱 Ver dispositivos conectados")
    show_connected_devices
    ;;
  "ℹ️ Ver información del hotspot")
    if [[ -f "$HOTSPOT_CONFIG" ]]; then
      source "$HOTSPOT_CONFIG"
      show_hotspot_info "$SSID" "$PASSWORD"
    else
      echo "No hay información de hotspot guardada" | rofi -dmenu -p "Info" -no-custom
    fi
    ;;
  "⬅️ Volver")
    exit 0
    ;;
  esac
}

# Manejar argumentos de línea de comandos
case "${1:-menu}" in
"create")
  create_hotspot
  ;;
"stop")
  stop_hotspot
  ;;
"menu" | *)
  hotspot_menu
  ;;
esac
