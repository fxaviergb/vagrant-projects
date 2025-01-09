#!/bin/bash
set -e

logger "Arrancando instalación y configuración de MongoDB"

USO="Uso: sudo install.sh [opciones]
Ejemplo:
sudo install.sh -u administrador -p password [-n 27017]

Opciones:
  -u usuario
  -p password
  -n número de puerto (opcional)
  -a muestra esta ayuda
"

function ayuda() {
  echo "${USO}"
  if [[ $1 ]]; then
    echo "$1"
  fi
}

# Gestionar los argumentos
while getopts ":u:p:n:a" OPCION; do
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
if [ -z "${USUARIO}" ]; then
  ayuda "El usuario (-u) debe ser especificado"
  exit 1
fi

if [ -z "${PASSWORD}" ]; then
  ayuda "La contraseña (-p) debe ser especificada"
  exit 1
fi

if [ -z "${PUERTO_MONGOD}" ]; then
  PUERTO_MONGOD=27017
fi

# Preparar el repositorio de MongoDB y añadir su clave apt
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 4B7C549A058F8B6B
echo "deb [arch=amd64,arm64] https://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/4.2 multiverse" | tee /etc/apt/sources.list.d/mongodb.list

# Instalar MongoDB si no está instalado
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
mkdir -p -m 755 /datos/bd /datos/log
chown mongodb /datos/log /datos/bd
chgrp mongodb /datos/log /datos/bd

# Crear el archivo de configuración de MongoDB
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
systemctl restart mongod
logger "Esperando a que mongod responda..."
sleep 15

# Crear el usuario con los datos proporcionados
mongo admin <<CREACION_DE_USUARIO
db.createUser({
  user: "${USUARIO}",
  pwd: "${PASSWORD}",
  roles: [
    { role: "root", db: "admin" },
    { role: "restore", db: "admin" }
  ]
})
CREACION_DE_USUARIO

logger "El usuario ${USUARIO} ha sido creado con éxito!"
exit 0
