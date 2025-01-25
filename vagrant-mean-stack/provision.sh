#!/bin/bash
set -e

# Actualizar e instalar Node.js y Nginx
sudo apt-get update -y
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs nginx

echo "NodeJS instalado correctamente."

# Configurar Nginx
cat <<EOF | sudo tee /etc/nginx/sites-available/app
server {
  listen 80;
  server_name _;

  location /express {
    proxy_pass http://localhost:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
  }

  location / {
    rewrite ^/angular(/.*)$ \$1 break;
    proxy_pass http://localhost:4000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_cache_bypass \$http_upgrade;
  }
}
EOF
sudo rm /etc/nginx/sites-enabled/default
sudo ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
sudo nginx -t && sudo systemctl restart nginx

echo "Nginx configurado correctamente."

# Instalar PM2 y Express
sudo npm install -g pm2
mkdir -p /home/ubuntu/app
cd /home/ubuntu/app
npm init -y
npm install express --save

# Crear aplicación con Express
cat <<EOF > /home/ubuntu/app/server.js
const express = require('express');
const path = require('path');
const app = express();

// Middleware para manejar datos JSON
app.use(express.json());

// Ruta principal de Express
app.get('/', (req, res) => {
  res.send('<html><body style="font-size:18px;">Hola <span style="color:blue;">MUNDO</span>. Express est\u00e1 funcionando correctamente.</body></html>');
});

// Ruta adicional para datos de ejemplo
app.get('/api/data', (req, res) => {
  const data = [{ id: 1, name: 'Juan', age: 30 }];
  res.json(data);
});


// Puerto de escucha
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
EOF

# Configurar PM2 para la app Express
sudo chown -R ubuntu:ubuntu /home/ubuntu/app
pm2 start /home/ubuntu/app/server.js --name express-server
sudo pm2 startup systemd -u ubuntu --hp /home/ubuntu
pm2 save

echo "PM2 configurado correctamente con Express."

# Instalar Angular CLI globalmente
sudo npm install -g @angular/cli

# Crear el proyecto Angular y configurarlo para desarrollo
mkdir -p /home/ubuntu
cd /home/ubuntu
sudo ng new angular-app --defaults --skip-git
cd /home/ubuntu/angular-app

echo "Ejecutando el proyecto Angular en modo desarrollo..."
npm install
pm2 start "ng serve --host 0.0.0.0 --port 4000 " --name angular-dev
pm2 save

# Asegurar permisos correctos
sudo chown -R ubuntu:ubuntu /home/ubuntu/angular-app

echo "Angular configurado para desarrollo y expuesto a trav\u00e9s de Nginx."
