#!/bin/bash

CONFIG_DIR="$HOME/.config/rofi/data"
LOG_FILE="$CONFIG_DIR/network.log"

# Crear directorio si no existe
mkdir -p "$CONFIG_DIR"

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

# Función para escanear redes WiFi
scan_wifi() {
  local nm_type=$(detect_network_manager)

  case $nm_type in
  "networkmanager")
    # Hacer rescan
    nmcli device wifi rescan &>/dev/null
    sleep 2

    # Obtener redes disponibles con mejor parsing
    nmcli -t -f SSID,SIGNAL,SECURITY device wifi list |
      grep -v '^:' |
      sort -t: -k2 -nr |
      while IFS=: read -r ssid signal security; do
        if [[ -n "$ssid" && "$ssid" != "--" ]]; then
          if [[ -z "$security" || "$security" == "--" ]]; then
            security="Abierta"
          fi
          printf "📶 %s (%s%%) - %s\n" "$ssid" "$signal" "$security"
        fi
      done
    ;;
  "iwd")
    iwctl station wlan0 scan &>/dev/null
    sleep 2
    iwctl station wlan0 get-networks | tail -n +5 | head -n -1 |
      awk '{
                ssid = $1
                signal = $2
                security = $3
                if(ssid != "" && ssid != "Available") {
                    printf "📶 %s (%s) - %s\n", ssid, signal, security
                }
            }'
    ;;
  *)
    echo "Error: No se encontró un administrador de red compatible"
    exit 1
    ;;
  esac
}

# Función mejorada para verificar si una red está guardada
is_network_saved() {
  local ssid="$1"
  # Buscar por nombre de conexión que coincida con el SSID
  nmcli connection show | awk -F'  +' '{print $1}' | grep -Fxq "$ssid"
}

# Función para obtener el nombre de conexión guardada
get_connection_name() {
  local ssid="$1"
  # Buscar conexiones que contengan el SSID
  nmcli connection show | grep "$ssid" | head -1 | awk -F'  +' '{print $1}'
}

# Función para conectar a WiFi
connect_wifi() {
  local ssid="$1"
  local security="$2"
  local nm_type=$(detect_network_manager)
  local password=""
  local max_attempts=3
  local attempt=1

  log_message "Intentando conectar a: $ssid (Seguridad: $security)"

  case $nm_type in
  "networkmanager")
    # 1. Primero intentar con conexión guardada
    if is_network_saved "$ssid"; then
      local connection_name=$(get_connection_name "$ssid")
      log_message "Red $ssid encontrada como conexión guardada: $connection_name"

      if nmcli connection up "$connection_name" 2>/dev/null; then
        notify-send "WiFi" "✅ Conectado a $ssid" -i network-wireless
        log_message "Conectado exitosamente usando conexión guardada: $connection_name"
        return 0
      else
        log_message "Falló conexión con perfil guardado, intentando conexión directa"
      fi
    fi

    # 2. Si no hay conexión guardada o falló, intentar conexión directa
    if [[ "$security" == "Abierta" ]] || [[ "$security" == "--" ]] || [[ -z "$security" ]]; then
      log_message "Intentando conexión a red abierta: $ssid"
      if nmcli device wifi connect "$ssid" 2>/dev/null; then
        notify-send "WiFi" "✅ Conectado a $ssid" -i network-wireless
        log_message "Conectado exitosamente a red abierta: $ssid"
        return 0
      fi
    else
      # Para redes seguras, intentar sin contraseña primero (por si acaso)
      if nmcli device wifi connect "$ssid" 2>/dev/null; then
        notify-send "WiFi" "✅ Conectado a $ssid" -i network-wireless
        log_message "Conectado a $ssid sin solicitar contraseña"
        return 0
      fi
    fi

    # 3. Si necesitamos contraseña
    if [[ "$security" != "Abierta" && "$security" != "--" && -n "$security" ]]; then
      while [[ $attempt -le $max_attempts ]]; do
        if [[ $attempt -gt 1 ]]; then
          password=$(rofi -dmenu -password -p "❌ Contraseña incorrecta. Intento $attempt/$max_attempts para $ssid:" -theme ~/.config/rofi/config/wifi.rasi 2>/dev/null)
        else
          password=$(rofi -dmenu -password -p "🔒 Contraseña para $ssid:" -theme ~/.config/rofi/config/wifi.rasi 2>/dev/null)
        fi

        # Si el usuario cancela
        if [[ -z "$password" ]]; then
          log_message "Conexión cancelada por el usuario"
          return 1
        fi

        # Intentar conexión con contraseña
        if nmcli device wifi connect "$ssid" password "$password" 2>/dev/null; then
          notify-send "WiFi" "✅ Conectado a $ssid" -i network-wireless
          log_message "Conectado exitosamente a $ssid con contraseña (intento $attempt)"
          return 0
        fi

        log_message "Intento $attempt fallido para $ssid"
        ((attempt++))
        sleep 1
      done
    fi
    ;;

  "iwd")
    # Lógica similar para iwd
    if [[ "$security" == "Abierta" ]] || [[ "$security" == "--" ]] || [[ -z "$security" ]]; then
      if iwctl station wlan0 connect "$ssid" 2>/dev/null; then
        notify-send "WiFi" "✅ Conectado a $ssid" -i network-wireless
        log_message "Conectado exitosamente a $ssid (red abierta)"
        return 0
      fi
    else
      # Para redes con seguridad en iwd
      while [[ $attempt -le $max_attempts ]]; do
        if [[ $attempt -gt 1 ]]; then
          password=$(rofi -dmenu -password -p "❌ Contraseña incorrecta. Intento $attempt/$max_attempts para $ssid:" -theme ~/.config/rofi/config/wifi.rasi 2>/dev/null)
        else
          password=$(rofi -dmenu -password -p "🔒 Contraseña para $ssid:" -theme ~/.config/rofi/config/wifi.rasi 2>/dev/null)
        fi

        if [[ -z "$password" ]]; then
          log_message "Conexión cancelada por el usuario"
          return 1
        fi

        if printf "%s\n" "$password" | iwctl station wlan0 connect "$ssid" 2>/dev/null; then
          notify-send "WiFi" "✅ Conectado a $ssid" -i network-wireless
          log_message "Conectado exitosamente a $ssid con contraseña"
          return 0
        fi

        ((attempt++))
        sleep 1
      done
    fi
    ;;
  esac

  # Si llegamos aquí, falló la conexión
  log_message "Falló la conexión a $ssid después de todos los intentos"
  notify-send "WiFi" "❌ Error: No se pudo conectar a $ssid" -i network-wireless-disconnected
  return 1
}

# Función principal para mostrar redes y conectar
wifi_menu() {
  # Mostrar mensaje de escaneo
  echo "🔍 Escaneando redes WiFi..." | rofi -dmenu -p "WiFi" -no-custom -theme ~/.config/rofi/config/wifi.rasi 2>/dev/null &
  local rofi_pid=$!

  # Escanear redes
  local networks=$(scan_wifi)

  # Cerrar mensaje de escaneo
  kill $rofi_pid 2>/dev/null
  wait $rofi_pid 2>/dev/null

  if [[ -z "$networks" ]]; then
    echo "❌ No se encontraron redes WiFi" | rofi -dmenu -p "WiFi" -no-custom -theme ~/.config/rofi/config/wifi.rasi 2>/dev/null
    return 1
  fi

  # Agregar opciones adicionales
  local options="🔄 Actualizar lista de redes
🔌 Desconectar WiFi
$networks"

  # Mostrar menú de selección
  local choice=$(echo -e "$options" | rofi -dmenu -p "Seleccionar red WiFi" -i -theme ~/.config/rofi/config/wifi.rasi 2>/dev/null)

  case "$choice" in
  "🔄 Actualizar lista de redes")
    wifi_menu
    ;;
  "🔌 Desconectar WiFi")
    if nmcli device disconnect wlan0 2>/dev/null || nmcli device disconnect wifi 2>/dev/null; then
      notify-send "WiFi" "📶 WiFi desconectado" -i network-wireless-disconnected
      log_message "WiFi desconectado manualmente"
    else
      notify-send "WiFi" "❌ Error al desconectar WiFi" -i network-wireless-disconnected
    fi
    ;;
  "")
    # Usuario canceló
    return 0
    ;;
  *)
    # Parsear la selección
    if [[ "$choice" =~ ^📶\ (.+)\ \(([0-9]+)%\)\ -\ (.+)$ ]]; then
      local ssid="${BASH_REMATCH[1]}"
      local signal="${BASH_REMATCH[2]}"
      local security="${BASH_REMATCH[3]}"

      log_message "Usuario seleccionó: SSID='$ssid', Señal=$signal%, Seguridad='$security'"
      connect_wifi "$ssid" "$security"
    else
      log_message "Error: No se pudo parsear la selección: $choice"
      notify-send "WiFi" "❌ Error: Selección inválida" -i network-wireless-disconnected
    fi
    ;;
  esac
}

# Función para mostrar estado actual
show_status() {
  local nm_type=$(detect_network_manager)
  case $nm_type in
  "networkmanager")
    nmcli device status | grep wifi
    echo "---"
    nmcli connection show --active | grep wifi
    ;;
  "iwd")
    iwctl station wlan0 show
    ;;
  esac
}

# Manejo de argumentos
case "${1:-}" in
"status")
  show_status
  ;;
"scan")
  scan_wifi
  ;;
*)
  # Verificar que el directorio de configuración exista
  if [[ ! -d "$CONFIG_DIR" ]]; then
    mkdir -p "$CONFIG_DIR"
  fi
  wifi_menu
  ;;
esac
