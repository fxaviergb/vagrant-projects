#!/bin/bash
set -e

logger "Arrancando instalación y configuración de MongoDB"

USO="Uso: sudo install-optimized.sh [opciones]
Ejemplo:
sudo install-optimized.sh [-u administrador -p password -n 27017] [-f config.ini]

Opciones:
  -u usuario
  -p password
  -n número de puerto (opcional)
  -f archivo de configuración (opcional)
  -a muestra esta ayuda
"

function ayuda() {
  echo "${USO}"
  if [[ $1 ]]; then
    echo "$1"
  fi
}

# Función para cargar parámetros desde un archivo de configuración
function cargar_configuracion() {
  local archivo=$1
  if [[ -f $archivo ]]; then
    while IFS='=' read -r clave valor; do
    # Validar que la línea tenga el formato clave=valor
      if [[ -z "$clave" || -z "$valor" || "$clave" =~ ^\s*$ || "$valor" =~ ^\s*$ ]]; then
        echo "El archivo no tiene un formato válido. Formato esperado: clave=valor"
        exit 1
      fi
      case $clave in
        user) USUARIO=$valor ;;
        password) PASSWORD=$valor ;;
        port) PUERTO_MONGOD=$valor ;;
      esac
    done < "$archivo"
  else
    echo "El archivo de configuración especificado no existe: $archivo"
    exit 1
  fi
}

# Gestionar los argumentos
echo "Leyendo parametros"
while getopts ":u:p:n:f:a" OPCION; do
  case ${OPCION} in
    u ) 
      USUARIO=$OPTARG
      echo "Parámetro USUARIO establecido con '${USUARIO}'"
      ;;
    p ) 
      PASSWORD=$OPTARG
      echo "Parámetro PASSWORD establecido"
      ;;
    n ) 
      PUERTO_MONGOD=$OPTARG
      echo "Parámetro PUERTO_MONGOD establecido con '${PUERTO_MONGOD}'"
      ;;
    f ) 
      CONFIG_FILE=$OPTARG
      echo "Archivo de configuración especificado: '${CONFIG_FILE}'"
      cargar_configuracion "$CONFIG_FILE"
      ;; 
    a ) 
      ayuda
      exit 0
      ;;
    : ) 
      ayuda "Falta el parámetro para -$OPTARG"
      exit 1
      ;;
    \?) 
      ayuda "La opción no existe: $OPTARG"
      exit 1
      ;;
  esac
done

# Validar argumentos requeridos
echo "Verificando validez de parametros recibidos"
if [ -z "${USUARIO}" ]; then
  ayuda "El usuario debe ser especificado (-u o -f config.ini)"
  exit 1
fi

if [ -z "${PASSWORD}" ]; then
  ayuda "La contraseña debe ser especificada (-p o -f config.ini)"
  exit 1
fi

if [ -z "${PUERTO_MONGOD}" ]; then
  PUERTO_MONGOD=27017
fi

# Preparar el repositorio de MongoDB y añadir su clave apt
echo "Obteniendo repositorio de MongoDB"
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 4B7C549A058F8B6B
#apt-key adv --keyserver hkp://keys.openpgp.org:80 --recv 4B7C549A058F8B6B
echo "deb [arch=amd64,arm64] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/4.2 multiverse" | tee /etc/apt/sources.list.d/mongodb.list

# Instalar MongoDB si no está instalado
echo "Instalando MongoDB"
if [[ -z "$(mongo --version 2>/dev/null | grep '4.2.1')" ]]; then
  apt-get -y update && \
  apt-get install -y \
    mongodb-org=4.2.1 \
    mongodb-org-server=4.2.1 \
    mongodb-org-shell=4.2.1 \
    mongodb-org-mongos=4.2.1 \
    mongodb-org-tools=4.2.1 && \
  rm -rf /var/lib/apt/lists/* && \
  pkill -u mongodb || true && \
  pkill -f mongod || true && \
  rm -rf /var/lib/mongodb
fi

# Crear carpetas de logs y datos con sus permisos
echo "Creando carpetas y permisos de usuario"
mkdir -p -m 755 /datos/bd /datos/log
chown mongodb /datos/log /datos/bd
chgrp mongodb /datos/log /datos/bd

# Crear el archivo de configuración de MongoDB
echo "Creando archivo de configuracion"
mv /etc/mongod.conf /etc/mongod.conf.orig
cat <<MONGOD_CONF > /etc/mongod.conf
# /etc/mongod.conf
systemLog:
  destination: file
  path: /datos/log/mongod.log
  logAppend: true
storage:
  dbPath: /datos/bd
  engine: wiredTiger
  journal:
    enabled: true
net:
  port: ${PUERTO_MONGOD}
security:
  authorization: enabled
MONGOD_CONF

# Reiniciar el servicio para aplicar la configuración
echo "Reiniciando servicio mongod"
systemctl restart mongod

# Verificar si el servicio está activo
for i in {1..30}; do
  if mongo --eval "db.runCommand({ connectionStatus: 1 })" &>/dev/null; then
    echo "El servicio mongod está activo y aceptando conexiones."
    break
  fi
  echo "Esperando a que mongod se inicie (intento $i)..."
  sleep 1
  if [[ $i -eq 30 ]]; then
    echo "Error: el servicio mongod no se inició a tiempo o no acepta conexiones."
    exit 1
  fi
done

# Crear el usuario con los datos proporcionados
echo "Creando usuario"
mongo admin --eval '
db.createUser({
  user: "'"${USUARIO}"'",
  pwd: "'"${PASSWORD}"'",
  roles: [
    { role: "root", db: "admin" },
    { role: "restore", db: "admin" }
  ]
})'

echo "El usuario ${USUARIO} ha sido creado con éxito!"
exit 0
