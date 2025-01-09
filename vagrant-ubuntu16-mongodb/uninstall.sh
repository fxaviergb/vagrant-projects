#!/bin/bash
set -e

echo "Detener el servicio de MongoDB"
sudo systemctl stop mongod

echo "Desinstalar MongoDB"
sudo apt-get purge -y mongodb-org mongodb-org-server mongodb-org-shell mongodb-org-mongos mongodb-org-tools libcurl3
#sudo apt-get purge -y libcurl3 libcurl4
sudo apt-get autoremove -y


echo "Eliminar configuraciones y datos"
sudo rm -r /var/log/mongodb
#sudo rm -r /var/lib/mongodb
sudo rm /etc/mongod.conf
sudo rm /etc/mongod.conf.orig
sudo rm /etc/apt/sources.list.d/mongodb.list

mongo --version
