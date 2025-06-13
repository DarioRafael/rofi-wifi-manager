#!/bin/bash

# Launcher principal para el Network Manager de Rofi
SCRIPTS_DIR="$HOME/.config/rofi/scripts"

# Verificar que existan los scripts necesarios
if [[ ! -f "$SCRIPTS_DIR/network-manager.sh" ]]; then
  notify-send "Error" "Scripts de red no encontrados en $SCRIPTS_DIR" -i dialog-error
  exit 1
fi

# Hacer ejecutables todos los scripts
chmod +x "$SCRIPTS_DIR"/*.sh

# Ejecutar el script principal
bash "$SCRIPTS_DIR/network-manager.sh"
